---
title: MCP Server开发实践
date: 2025-05-16
tags:
  - AI
  - MCP
  - 实践
categories:
  - AI
---

# MCP Server开发实践

上一篇文章我们介绍了MCP的基本原理，但是对于开发者来说更关心如何实现我们的自己的MCP Server，接下来我们将使用MCP提供的java sdk和spring-ai来实现一个MCP Server。

## 构建Spring Boot服务

技术选型：
- Spring Boot 3.4.2，因为Spring AI支持的Spring Boot版本为3.4.x

> Spring AI supports Spring Boot 3.4.x. When Spring Boot 3.5.x is released, we will support that as well.
- JDK 17，Spring Boot3需要使用JDK 17
- spring-ai-mcp-server-webmvc-spring-boot-starter 1.0.0-M6，Spring AI支持三种方式提供服务，这里采用`webmvc`
    - Standard Input/Output (STDIO) - spring-ai-starter-mcp-server
    - Spring MVC (Server-Sent Events) - spring-ai-starter-mcp-server-webmvc
    - Spring WebFlux (Reactive SSE) - spring-ai-starter-mcp-server-webflux
- httpclient5，将现有服务的HTTP接口暴露为MCP Server

`pom.xml`文件示例：
```xml
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-dependencies</artifactId>
                <version>3.4.2</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <dependencies>
        <!-- MCP -->
        <dependency>
            <groupId>org.springframework.ai</groupId>
            <artifactId>spring-ai-mcp-server-webmvc-spring-boot-starter</artifactId>
            <version>1.0.0-M6</version>
        </dependency>

        <!-- Lombok -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <optional>true</optional>
        </dependency>

        <!-- Apache HttpClient -->
        <dependency>
            <groupId>org.apache.httpcomponents.client5</groupId>
            <artifactId>httpclient5</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.httpcomponents.core5</groupId>
            <artifactId>httpcore5</artifactId>
        </dependency>
        <dependency>
            <groupId>org.apache.httpcomponents.core5</groupId>
            <artifactId>httpcore5-h2</artifactId>
        </dependency>

        <!-- Spring Boot Starter -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
    </dependencies>
```

## MCP配置

- application.yml
```yaml
spring:
  application:
    name: mcp-name
  ai:
    mcp:
      server:
        name: mcp-name
        version: 1.0.0
        type: SYNC
        sse-endpoint: /sse
```

- Server实现，这里直接通过转发的方式将现有的HTTP接口暴露为MCP Server
```java
/**
 * @date 2025/03/27 14:52
 **/
@Service
public class SmdMcpService {

    @Autowired
    private RestTemplate restTemplate;

    @Value("${smd.service.url}")
    private String smdServiceUrl;

    @Tool(name = "getSmdInfo", description = "获取表结构信息")
    public String getSmdInfo(@ToolParam(description = "业务系统") String businessSystem,
                             @ToolParam(description = "表名") Set<String> tableNames) {
        Map<String, Object> params = new HashMap<>();
        params.put("businessSystem", businessSystem);
        params.put("tableNames", tableNames);

        ResponseEntity<String> response = restTemplate.postForEntity(
                smdServiceUrl + "/mcp/api/getSmdInfo",
                params,
                String.class);
        return response.getBody();
    }

    @Tool(name = "getCRUDCode", description = "根据表名生成增删改查代码")
    public List<Map<String, Object>> getCRUDByTable(@ToolParam(description = "业务系统") String businessSystem,
                                    @ToolParam(description = "表名") Set<String> tableNames,
                                    @ToolParam(description = "模块名，非必填") String moduleName
                                 ) {
        Map<String, Object> params = new HashMap<>();
        params.put("businessSystem", businessSystem);
        params.put("tableNames", tableNames);
        params.put("moduleName", moduleName);
        params.put("author", "smd-mcp");

        HttpEntity<Map<String, Object>> httpEntity =  new HttpEntity<>(params);
        ResponseEntity<List<Map<String, Object>>> response = restTemplate.exchange(
                smdServiceUrl + "/mcp/api/crud",
                HttpMethod.POST,
                httpEntity,
                new ParameterizedTypeReference<List<Map<String, Object>>>() {});
        return response.getBody();
    }
}
```

- 将对应服务暴露为Mcp Tools
```java
/**
 * MCP配置类
 *
 * @author AI Assistant
 * @date 2024/03/21
 */
@Configuration
@Slf4j
public class McpConfig {

    @Bean
    public ToolCallbackProvider smdToolCallbackProvider(SmdMcpService smdMcpService, RulesMcpService rulesMcpService) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(smdMcpService, rulesMcpService)
                .build();
    };
} 
```

## 测试MCP

使用支持MCP的客户端进行测试，客户端支持情况可查看：[https://modelcontextprotocol.io/clients](https://modelcontextprotocol.io/clients)

这里使用Cursor进行测试：

配置`mcp.json`
```json
{
    "mcpServers": {
      "mcp-name": {
        "url": "http://localhost:8089/sse",
        "env": {
          "API_KEY": "value"
        }
      }
    }
  }
```

配置后即可看到MCP Server提供的Tools，如下图所示：
![Cursor MCP配置.png](https://mmbiz.qpic.cn/mmbiz_png/14Blum0GwI7zfMWdeXcoUMs1Rv8Qc6atGoTgk9KpicA9CxVpLI8z2A8FgbFlt6p0GPekfhbxAic6giaqTj6TzeL2A/640?wx_fmt=png&amp;from=appmsg)

## MCP思考

MCP 还处于发展初期，现阶段更重要的是生态构建，基于统一标准下构筑的生态也会正向的促进整个领域的发展。

对于普通开发者我们可以直接使用已有的MCP工具平台：[https://mcp.so/](https://mcp.so/)

对于企业，我们可以通过代理的方式将已有HTTP接口暴露为MCP Server：
- 零侵入改造：无需修改原有HTTP服务代码即可获得MCP能力
- 跨模型兼容：让原本不支持MCP的传统服务获得与大模型生态无缝对接的能力
- 低成本投入：已有业务接入MCP生态的改造周期大幅缩短

**后续考虑将其做成MCP代理服务，通过简单配置即可将已有业务转换为MCP Server，为AI智能体打开潘多拉的魔盒**

参考文档：
- https://modelcontextprotocol.io/sdk/java/mcp-server
- https://docs.spring.io/spring-ai/reference/api/mcp/mcp-server-boot-starter-docs.html
- https://docs.spring.io/spring-ai/reference/getting-started.html
