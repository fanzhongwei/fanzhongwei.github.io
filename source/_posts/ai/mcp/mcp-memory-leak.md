---
title: Spring AI MCP服务内存泄漏排查实录：从堆分析到源码修复
date: 2025-07-03
tags:
  - AI
  - MCP
  - 性能优化
categories:
  - AI
---

# Spring AI MCP服务内存泄漏排查实录：从堆分析到源码修复

> Spring AI构建的MCP服务频繁OOM？本文完整记录问题排查全链路：
1️⃣ 通过MAT精准定位WebMvcSseServerTransport中未释放的会话占99.59%内存
2️⃣ 发现SDK 0.7.0版本仅在异常时清理会话的设计缺陷
3️⃣ 升级1.0.0版本后仍存在异步连接残留问题
4️⃣ 最后采用"心跳检测+异常熔断"双保险机制
👉 关键方案：定时发送轻量级消息sendNotification，实现自动回收失效连接，彻底解决内存泄漏。附完整堆分析截图、源码对比！


上一篇文章我们介绍了如何使用Spring AI快速构建一个MCP Server：[Spring AI+MCP实战：零代码改造将传统服务接入大模型生态](https://mp.weixin.qq.com/s/Bvn2IVuAQNrhssiFSSMTNQ?poc_token=HGtmYmijy4ZbqRu3-KFeD4sMclJshRabLO0qdeFg)，但是服务启动一段时间后，总是是内存溢出，导致MCP服务时不时就不可用，必须得重启才能解决。

配置java参数当内存溢出时自动转储堆，然后分析堆内存，终于发现了罪魁祸首，接下来就让我们一起来看看罪魁祸首是谁。


## 分析堆内存

使用`MAT（Eclipse Memory Analyzer）`打开自动转储的堆文件，加载完成后打开`Leak Suspects`可以发现内存泄露的可疑点：

![内存泄露疑点.png](https://mmbiz.qpic.cn/mmbiz_png/14Blum0GwI7qnJcG2Fy61JgxGRia35guVicKn8Fp6IwEasDAuhldqkPvWL4HrXz3jRDS41WrFYHbcbGBIiaqI37MA/640?wx_fmt=png&amp;from=appmsg)

从上图可以发现，由`io.modelcontextprotocol.server.transport.WebMvcSseServerTransport @ 0x700730098`对象持有的`java.util.concurrent.ConcurrentHashMap$Node[]`占用了99.59%的内存。

到这里基本就可以确定内存泄露的罪魁祸首就是`WebMvcSseServerTransport`，具体是其中的哪个对象呢，让我们继续分析。

点击`Eclipse Memory Analyzer`上的`dominator_tree`可以看到堆内存中对象的树形结构信息，这里根据`Retained Heap`降序排列，可以看到占用内存最多的对象`java.util.concurrent.ConcurrentHashMap$Node[]`，右键 -》Path To GC Roots -》with all references，可以看到泄露对象到gc roots的路径，可以清晰的看到是被谁持有但一直未释放。

![内存泄露GcRoots.png](https://mmbiz.qpic.cn/mmbiz_png/14Blum0GwI7qnJcG2Fy61JgxGRia35guVjyjLhlxSicRkso4VVxPup46Id1YP2dHEccRhnuAT2N1EqT27hK536Ug/640?wx_fmt=png&amp;from=appmsg)

到这里我们知道了是`WebMvcSseServerTransport#sessions`属性持有了有大量的Map节点，但一直没释放，最终导致JVM内存溢出了。

> MAT工具的文档详见文末的参考链接


## 源码分析

之前2025年3月份根据官方文档: [https://docs.spring.io/spring-ai/reference/api/mcp/mcp-server-boot-starter-docs.html](https://docs.spring.io/spring-ai/reference/api/mcp/mcp-server-boot-starter-docs.html)集成的时候，引入starter为：
```xml
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-mcp-server-webmvc-spring-boot-starter</artifactId>
    <version>1.0.0-M6</version>
</dependency>
```

其中引入的`io.modelcontextprotocol.sdk:mcp-spring-webmvc`的版本为0.7.0，`WebMvcSseServerTransport`的**核心实现（省略部分与本次内存溢出问题无关的代码）**如下：

```
public class WebMvcSseServerTransport implements ServerMcpTransport {

    private final ConcurrentHashMap<String, ClientSession> sessions;
    
    private ServerResponse handleSseConnection(ServerRequest request) {
        if (this.isClosing) {
            return ServerResponse.status(HttpStatus.SERVICE_UNAVAILABLE).body("Server is shutting down");
        } else {
            String sessionId = UUID.randomUUID().toString();
            logger.debug("Creating new SSE connection for session: {}", sessionId);

            try {
                return ServerResponse.sse((sseBuilder) -> {
                    ClientSession session = new ClientSession(sessionId, sseBuilder);
                    this.sessions.put(sessionId, session);

                    try {
                        session.sseBuilder.id(session.id).event("endpoint").data(this.messageEndpoint);
                    } catch (Exception e) {
                        logger.error("Failed to poll event from session queue: {}", e.getMessage());
                        sseBuilder.error(e);
                    }

                });
            } catch (Exception e) {
                logger.error("Failed to send initial endpoint event to session {}: {}", sessionId, e.getMessage());
                // 只有出现异常的时候才将session移除
                this.sessions.remove(sessionId);
                return ServerResponse.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }
        }
    }
    
    private static class ClientSession {
        private final String id;
        private final ServerResponse.SseBuilder sseBuilder;

        ClientSession(String id, ServerResponse.SseBuilder sseBuilder) {
            this.id = id;
            this.sseBuilder = sseBuilder;
            WebMvcSseServerTransport.logger.debug("Session {} initialized with SSE emitter", id);
        }

        void close() {
            WebMvcSseServerTransport.logger.debug("Closing session: {}", this.id);

            try {
                // session关闭时，只将sseBuilder设置为完成
                this.sseBuilder.complete();
                WebMvcSseServerTransport.logger.debug("Successfully completed SSE emitter for session {}", this.id);
            } catch (Exception e) {
                WebMvcSseServerTransport.logger.warn("Failed to complete SSE emitter for session {}: {}", this.id, e.getMessage());
            }

        }
    }

}

```

从上面代码可以发现，在MCP的ClientSession关闭时，只是将sseBuilder设置为完成；仅当`handleSseConnection`中出现异常时才会将ClientSession从sessions中移除，估计是想客户端一直复用这个连接吧。

那么正常情况下，这个session就会一直存在于`WebMvcSseServerTransport#sessions`属性中，而`WebMvcSseServerTransport`对象在MCP服务运行时会一直存活，因此一段时间后MCP服务就会因为`WebMvcSseServerTransport#sessions`属性内存泄露最终导致jvm的内存溢出。

## SDK升级

经过上面的源码分析，我们知道了内存泄露的具体原因是`WebMvcSseServerTransport#sessions`的ClientSession一直在增长，因此只需要在ClientSession完成或异常的时候将其从sessions中移除即可。

经查看最新的官方文档: [https://docs.spring.io/spring-ai/reference/api/mcp/mcp-server-boot-starter-docs.html](https://docs.spring.io/spring-ai/reference/api/mcp/mcp-server-boot-starter-docs.html)，其中对于`MCP Server Boot Starter`已经做了升级，升级到`1.0.0`版本后，可以看到最新的版本是由`WebMvcSseServerTransportProvider`来管理see请求的，处理sse请求的源码如下：

```java
    private ServerResponse handleSseConnection(ServerRequest request) {
        if (this.isClosing) {
            return ServerResponse.status(HttpStatus.SERVICE_UNAVAILABLE).body("Server is shutting down");
        } else {
            String sessionId = UUID.randomUUID().toString();
            logger.debug("Creating new SSE connection for session: {}", sessionId);

            try {
                return ServerResponse.sse((sseBuilder) -> {
                    sseBuilder.onComplete(() -> {
                        logger.debug("SSE connection completed for session: {}", sessionId);
                        this.sessions.remove(sessionId);
                    });
                    sseBuilder.onTimeout(() -> {
                        logger.debug("SSE connection timed out for session: {}", sessionId);
                        this.sessions.remove(sessionId);
                    });
                    WebMvcMcpSessionTransport sessionTransport = new WebMvcMcpSessionTransport(sessionId, sseBuilder);
                    McpServerSession session = this.sessionFactory.create(sessionTransport);
                    this.sessions.put(sessionId, session);

                    try {
                        sseBuilder.id(sessionId).event("endpoint").data(this.baseUrl + this.messageEndpoint + "?sessionId=" + sessionId);
                    } catch (Exception e) {
                        logger.error("Failed to send initial endpoint event: {}", e.getMessage());
                        sseBuilder.error(e);
                    }

                }, Duration.ZERO);
            } catch (Exception e) {
                logger.error("Failed to send initial endpoint event to session {}: {}", sessionId, e.getMessage());
                this.sessions.remove(sessionId);
                return ServerResponse.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }
        }
    }

```

其中可以看到，在请求完成、超时和异常情况下都会将session移除，这样应该就能解决内存溢出问题了。

**问题到这里真的解决了吗？**


## 解决方案

经过验证，发现升级后的SDK里面`WebMvcSseServerTransport#sessions`中存放的`McpServerSession`还是会一直存在，并没有移除。

可能是异步请求的请求，Cursor之类的客户端在创建MCP连接后，即使Cursor关闭后也没有主动去**告诉服务端断开连接**，也就是不会触发`onComplete`、`onTimeout`方法去将session移除。

于是，我们可以定时去检测`WebMvcSseServerTransport#sessions`中的`McpServerSession`是否还存活，如果客户端已经把连接关闭了，那么就将session移除。

```java
/**
 * session管理，避免内存溢出
 *
 * @date 2025/07/01 16:18
 **/
@Slf4j
@Configuration
@EnableScheduling
public class McpSessionConfig {
    
    @Autowired
    private WebMvcSseServerTransportProvider sseServerTransportProvider;
    
    @Value("${mcp.session.health-check-enabled:true}")
    private boolean healthCheckEnabled;
    
    @Value("${mcp.session.health-check-interval:1800000}")
    private long healthCheckInterval;
    
    @Value("${mcp.session.health-check-timeout:5000}")
    private long healthCheckTimeout;
    
    /**
     * 定时任务：定期执行session存活检测
     * 从sseServerTransportProvider中获取sessions，遍历检测session是否存活，
     * 使用sendNotification进行检测，检测失败的session需要自动移除
     */
    @Scheduled(fixedRateString = "${mcp.session.health-check-interval:1800000}")
    public void checkSessionHealth() {
        // 检查是否启用健康检测
        if (!healthCheckEnabled) {
            log.debug("MCP session健康检测已禁用");
            return;
        }
        try {
            log.info("开始执行MCP session存活检测任务");
            
            // 获取所有活跃的sessions
            Map<String, McpServerSession> sessionsMap = (Map<String, McpServerSession>) getFieldValue(sseServerTransportProvider, "sessions");
            if (null == sessionsMap || sessionsMap.isEmpty()) {
                log.info("当前没有活跃的MCP sessions");
                return;
            }
            
            log.info("检测到 {} 个活跃sessions，开始进行存活检测", sessionsMap.size());

            // 遍历检测每个session的存活状态
            List<CompletableFuture<Void>> futures = new CopyOnWriteArrayList<>();
            for (McpServerSession session : sessionsMap.values()) {
                // 使用sendNotification进行检测，getCurrentTime是一个MCP的Tool方法
                // 发送一个轻量级的ping消息来检测连接是否有效
                Mono<Void> mono = session.sendNotification("getCurrentTime");
                futures.add(mono.toFuture());
            }
            CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
            log.info("MCP session存活检测任务执行完成，剩余session数量：{}", sessionsMap.size());
        } catch (Exception e) {
            log.error("执行MCP session存活检测任务时发生异常", e);
        }
    }

    private Object getFieldValue(Object obj, String fieldName) {
        try {
            Field field = FieldUtils.getField(obj.getClass(), fieldName, true);
            field.setAccessible(true);
            return field.get(obj);
        } catch (Exception e) {
            log.error("获取字段值时发生异常", e);
            return null;
        }
    }
}
```

发送检测消息后`session.sendNotification("getCurrentTime")`，Tomcat中间件会检测到该sse连接是否还存活，如果连接已断开会有如下异常信息(省略部分堆栈)：
```
2025-07-02 14:01:31.064 [http-nio-8089-exec-13] ERROR o.a.c.c.C.[.[.[.[dispatcherServlet] - Servlet.service() for servlet [dispatcherServlet] threw exception
java.io.IOException: 断开的管道
	at java.base/sun.nio.ch.FileDispatcherImpl.write0(Native Method)
	at java.base/sun.nio.ch.SocketDispatcher.write(SocketDispatcher.java:62)
	at java.base/sun.nio.ch.IOUtil.writeFromNativeBuffer(IOUtil.java:132)
	at java.base/sun.nio.ch.IOUtil.write(IOUtil.java:97)
	at java.base/sun.nio.ch.IOUtil.write(IOUtil.java:53)
	at java.base/sun.nio.ch.SocketChannelImpl.write(SocketChannelImpl.java:532)
	...
	at io.modelcontextprotocol.server.transport.WebMvcSseServerTransportProvider$WebMvcMcpSessionTransport.lambda$sendMessage$0(WebMvcSseServerTransportProvider.java:364)
	at reactor.core.publisher.MonoRunnable.subscribe(MonoRunnable.java:49)
	at reactor.core.publisher.Mono.subscribe(Mono.java:4576)
	at reactor.core.publisher.Mono.subscribeWith(Mono.java:4641)
	at reactor.core.publisher.Mono.toFuture(Mono.java:5153)
	at com.teddy.smd.mcp.config.McpSessionConfig.checkSessionHealth(McpSessionConfig.java:74)
```

Tomcat中间件在`org.apache.catalina.core.AsyncContextImpl#doInternalDispatch`中检测到异常后，会将连接设置为完成：
```java
protected void doInternalDispatch() throws ServletException, IOException {
    if (log.isTraceEnabled()) {
        this.logDebug("intDispatch");
    }

    try {
        Runnable runnable = this.dispatch;
        this.dispatch = null;
        runnable.run();
        if (!this.request.isAsync()) {
            this.fireOnComplete();
        }

    } catch (RuntimeException x) {
        AtomicBoolean result = new AtomicBoolean();
        this.request.getCoyoteRequest().action(ActionCode.IS_IO_ALLOWED, result);
        if (!result.get()) {
            // 将连接设置为完成
            this.fireOnComplete();
        }

        if (x.getCause() instanceof ServletException) {
            throw (ServletException)x.getCause();
        } else if (x.getCause() instanceof IOException) {
            throw (IOException)x.getCause();
        } else {
            throw new ServletException(x);
        }
    }
}
```

连接设置为完成后，最终会触发`WebMvcSseServerTransport#handleSseConnection`方法中的`sseBuilder.onComplete`回调中将session进行移除
```java
sseBuilder.onComplete(() -> {
	logger.debug("SSE connection completed for session: {}", sessionId);
	sessions.remove(sessionId);
});
```

检测的日志输出情况如下：
```
2025-07-02 14:01:31.053 [scheduling-1] INFO  c.t.smd.mcp.config.McpSessionConfig - 检测到 15 个活跃sessions，开始进行存活检测
2025-07-02 14:01:31.062 [scheduling-1] ERROR i.m.s.t.WebMvcSseServerTransportProvider - Failed to send message to session a9af3b98-35fc-4769-b84f-fedbdc384977: ServletOutputStream failed to flush: java.io.IOException: 断开的管道
2025-07-02 14:01:31.063 [scheduling-1] ERROR i.m.s.t.WebMvcSseServerTransportProvider - Failed to send message to session 7b88ebdc-abd3-41fe-be98-75ed217dcfe6: ServletOutputStream failed to flush: java.io.IOException: 断开的管道
...
2025-07-02 14:01:31.063 [scheduling-1] INFO  c.t.smd.mcp.config.McpSessionConfig - MCP session存活检测任务执行完成，剩余session数量：4
```


到这里终于完美解决MCP服务因为连接泄露导致的内存溢出问题。


参考链接：
- https://docs.spring.io/spring-ai/reference/api/mcp/mcp-server-boot-starter-docs.html
- https://help.eclipse.org/latest/index.jsp?topic=/org.eclipse.mat.ui.help/welcome.html


