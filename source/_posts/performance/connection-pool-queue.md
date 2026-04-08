---
title: 性能优化-连接池排队问题
date: 2024-09-17
tags:
  - 性能优化
  - 连接池
  - 数据库
categories:
  - 性能优化
---

# 性能优化-连接池排队问题

数据库连接池中还有很多空闲连接，为什么应用的数据库操作都在排队等待**获取**和**归还**连接？

## 背景

生产环境系统上线前进行压测，应用共4个节点，每个节点4核8G，每个节点连接池大小1000，200业务并发（非单接口绝对并发）；从监控发现Druid连接池获取连接和释放连接都需要300ms左右的时间，这对于整个系统的吞吐量影响特别大。

> 某次查询数据库操作中方法调用堆栈耗时监控：
> com.alibaba.druid.pool.DruidDataSource.getConnection()：耗时327ms
> com.oceanbase.jdbc.JDBC4PreparedStatement.execute()：耗时3ms
> com.alibaba.druid.pool.DruidPooledConnection.close()：耗时294ms


## 问题排查过程

### 线程堆栈分析

dump应用的线程信息，发现有217个线程在等待获取数据库连接，有156个线程在等待释放数据库连接，关键线程信息如下所示：

```log
217个线程在等待获取数据库连接
"HSFBizProcessor-DEFAULT-8-thread-446" #1623 daemon prio=10 os_prio=0 tid=0x00007f436c8dc000 nid=0x341154 waiting on condition [0x00007f4310d17000]
   java.lang.Thread.State: WAITING (parking)
	at sun.misc.Unsafe.park(Native Method)
	- parking to wait for  <0x000000055d50cf68> (a java.util.concurrent.locks.ReentrantLock$FairSync)
	at java.util.concurrent.locks.LockSupport.park(LockSupport.java:175)
	at java.util.concurrent.locks.AbstractQueuedSynchronizer.parkAndCheckInterrupt(AbstractQueuedSynchronizer.java:836)
	at java.util.concurrent.locks.AbstractQueuedSynchronizer.doAcquireInterruptibly(AbstractQueuedSynchronizer.java:897)
	at java.util.concurrent.locks.AbstractQueuedSynchronizer.acquireInterruptibly(AbstractQueuedSynchronizer.java:1222)
	at java.util.concurrent.locks.ReentrantLock.lockInterruptibly(ReentrantLock.java:335)
	at com.alibaba.druid.pool.DruidDataSource.getConnectionInternal(DruidDataSource.java:1632)
	...

	
156个线程在等待释放数据库连接
"HSFBizProcessor-DEFAULT-8-thread-443" #1620 daemon prio=10 os_prio=0 tid=0x00007f436404e000 nid=0x341151 waiting on condition [0x00007f4310e9b000]
   java.lang.Thread.State: WAITING (parking)
	at sun.misc.Unsafe.park(Native Method)
	- parking to wait for  <0x000000055d50cf68> (a java.util.concurrent.locks.ReentrantLock$FairSync)
	at java.util.concurrent.locks.LockSupport.park(LockSupport.java:175)
	at java.util.concurrent.locks.AbstractQueuedSynchronizer.parkAndCheckInterrupt(AbstractQueuedSynchronizer.java:836)
	at java.util.concurrent.locks.AbstractQueuedSynchronizer.acquireQueued(AbstractQueuedSynchronizer.java:870)
	at java.util.concurrent.locks.AbstractQueuedSynchronizer.acquire(AbstractQueuedSynchronizer.java:1199)
	at java.util.concurrent.locks.ReentrantLock$FairSync.lock(ReentrantLock.java:224)
	at java.util.concurrent.locks.ReentrantLock.lock(ReentrantLock.java:285)
	at com.alibaba.druid.pool.DruidDataSource.recycle(DruidDataSource.java:2016)
	...
	
```

### 怀疑数据库连接泄露

数据库连接泄露的问题主要有两类：
1. 手动获取数据库连接，未释放。
2. 手动开始事务，未结束（提交或回滚）。

全局搜索项目源码，未发现以上两种情况。根据压测结束后堆dump信息（没有开连接池信息打印），从堆信息中发现DruidDataSource对象的**池中连接数poolingCount=1000**，也就是说所有的连接已全部归还到连接池中。

因此数据库连接泄露的嫌疑被排除。


### 怀疑有慢sql或者有大事务长时间占用连接

根据线程信息分析，正在执行数据库操作`com.oceanbase.jdbc.JDBC4PreparedStatement.execute`的线程仅仅只有一个。因此有大量慢sql，导致数据库连接池耗尽的嫌疑被排除。

从线程信息中不能直接发现是否有大事务长时间占用连接，根据源码分析又仿佛大海捞针，这里再看看堆dump信息，发现DruidDataSource对象的**活跃连接数峰值activePeak=303**，也就是说连接池中始终都有空闲可用的连接。因此有大事务长时间占用连接，导致数据库连接池耗尽的嫌疑被排除。

### 怀疑连接池本身的性能问题

从线程信息中发现，所有的获取和释放连接的线程都在等待同一把锁（公平锁）：`- parking to wait for  <0x000000055d50cf68> (a java.util.concurrent.locks.ReentrantLock$FairSync)`，对应DruidDataSource的关键源码如下：
```java
    
    private DruidPooledConnection getConnectionInternal(long maxWait) throws SQLException {
        ...
        
        DruidConnectionHolder holder;
        for (boolean createDirect = false;;) {
            ...
            try {
                lock.lockInterruptibly();
            } catch (InterruptedException e) {
                connectErrorCountUpdater.incrementAndGet(this);
                throw new SQLException("interrupt", e);
            }
            
            try {
                ...
                
                if (maxWait > 0) {
                    // 配置了连接获取超时时间
                    holder = pollLast(nanos);
                } else {
                    // 未配置连接获取超时时间
                    holder = takeLast();
                }
                ...
            }
            ...
            holder.incrementUseCount();

            DruidPooledConnection poolalbeConnection = new DruidPooledConnection(holder);
            return poolalbeConnection;
        }
    }

    /**
     * 回收连接
     */
    protected void recycle(DruidPooledConnection pooledConnection) throws SQLException {
        ...
        // 获取连接池的锁，归还holder，将其放入连接池中
        lock.lock();
        try {
            if (holder.active) {
                activeCount--;
                holder.active = false;
            }
            closeCount++;

            result = putLast(holder, currentTimeMillis);
            recycleCount++;
        } finally {
            lock.unlock();
        }
        ...
    }

```

查阅Druid的文档，发现有介绍Druid锁的公平模式问题：[https://github.com/alibaba/druid/wiki/Druid锁的公平模式问题](https://github.com/alibaba/druid/wiki/Druid%E9%94%81%E7%9A%84%E5%85%AC%E5%B9%B3%E6%A8%A1%E5%BC%8F%E9%97%AE%E9%A2%98)

| 版本            | 处理方式                                                                                       | 效果                                     |
| ------------- | ------------------------------------------------------------------------------------------ | -------------------------------------- |
| 0.2.3之前       | unfair                                                                                     | 并发性能很好。<br><br>maxWait>0的配置下，出现严重不公平现象 |
| 0.2.3 ~ 0.2.6 | fair                                                                                       | 公平，但是并发性能很差                            |
| 0.2.7         | 通过构造函数传入参数指定fair或者unfair，缺省fair                                                            | 按需要配置，但是比较麻烦                           |
| 0.2.8         | 缺省unfair，通过构造函数传入参数指定fair或者unfair；<br><br>如果DruidDataSource还没有初始化，修改maxWait大于0，自动转换为fair模式 | 智能配置，能够兼顾性能和公平性                        |

应用确实配置了maxWait参数，从线程信息中看也确实是使用的公平锁`ReentrantLock$FairSync`，在高并发下性能表现很差。

到此为止，基本可以确定<font color=red>**公平锁**的并发性能差导致连接池排队等待**获取**和**归还**连接问题</font>，下面让我们来验证下公平锁和非公平锁对性能的影响到底有多大。


## 锁的公平模式性能验证

- 测试接口每次请求中并发查询30次简单sql，具体代码如下：
```java
public String selectTest() {
    List<Promise<?>> promises = new ArrayList<>();
    for (int i = 0; i < 30; i++) {
        Promise<String> promise = CompletableHelper.promise(() -> {
            return (String) SqlRunner.db()
                                     .selectObj("select '1' from dual");
        });
        promises.add(promise);
    }
    List<?> results = CompletableHelper.waitAll(promises);
    return StringUtils.join(results, ",");
}
```
- 应用配置：
    - 单节点4核16G
    - JVM内存：-Xms5120m -Xmx5120m -Xmn1706m

- 压测、监控工具
    - JMeter
    - javaagent：[性能优化利器-JavaAgent](https://mp.weixin.qq.com/s/VQTsvtWocQx7veO3saNUqA)
- 压测结果：

| 锁模式  | 数据库连接池大小 | 并发数    | 获取连接：getConnectionInternal<br><br>平均耗时ms | 归还连接：recycle<br><br>平均耗时ms | 连接池最大活跃数：activePeak | 接口请求样本数    | 接口请求响应平均ms | 接口请求响应90%百分位ms | 接口请求响应最小值ms | 接口请求响应最大值ms | 接口请求吞吐量       |
| ---- | -------- | --- | ------    | ----- | -------- | ----- | ----- | ---------                      | ---------------------------------------- | -------------------------- | ------------------- |
| 非公平锁 | 200      | 100 | 5                                        | 1                          | 200                 | 631733 |  534   | 972      | 7     | 5689  | 187.2/sec                      |
| 公平锁  | 200      | 100 | 107                                      | 62                         | 200                 | 292050  | 959   | 1324     | 354   | 3533  | 104.1/sec                      |
| 非公平锁 | 500      | 100 | 1.8                                      | 2.2                        | 500                 | 220793  | 525   | 950      | 7     | 2976  | 189.0/sec                      |
| 公平锁  | 500      | 100 | 71                                       | 70                         | 500                 | 152745  | 785   | 1207     | 347   | 5407  | 127.2/sec                      |
| 非公平锁 | 1000     | 100 | 1                                        | 1.5                        | 510                 | 232726 | 520   | 947      | 8     | 2547  | 193.9/sec                      |
| 公平锁  | 1000     | 100 | 83                                       | 82                         | 557                 | 134607  | 891   | 1367     | 68    | 5440  | 112.1/sec                      |


- 压测结论：非公平锁模式下获取和归还连接的性能遥遥领先公平锁模式。


## 解决方案

数据库连接池推荐配置（连接池大小需根据实际情况调整）
- initialSize：500
- minIdle：500
- maxActive：500
- maxWait：6000
- keepAlive：true
- 在连接池初始化之前，手动设置：dataSouce.setUseUnfairLock(true)

> 更多推荐配置见：[https://github.com/alibaba/druid/wiki/DruidDataSource配置](https://github.com/alibaba/druid/wiki/DruidDataSource%E9%85%8D%E7%BD%AE)


修改Druid连接池配置后，更新应用到生产环境复测（200并发），javaagent监控druid相关方法耗时从几百ms降低到不足个位数，事务操作耗时从平均10s降低到平均2s，至此数据库操作都在排队等待获取和归还连接问题得以解决。


尽管极端情况下，在连接池中的连接不够用大量线程争用连接时，unfair模式的ReentrantLock.tryLock方法存在严重不公的现象，个别线程会等到超时了还获取不到连接。


个人观点：数据库连接池的锁调整为非公平锁<font  color=red>**整体来看利远大于弊**</font>，**如果真的有这么大的并发量，更应该增加应用节点数量，缓解单节点的压力。**


## 参考文档
- [性能优化利器-JavaAgent](https://mp.weixin.qq.com/s/VQTsvtWocQx7veO3saNUqA)
- [https://github.com/alibaba/druid/wiki/DruidDataSource配置](https://github.com/alibaba/druid/wiki/DruidDataSource%E9%85%8D%E7%BD%AE)
- [https://github.com/alibaba/druid/wiki/Druid锁的公平模式问题](https://github.com/alibaba/druid/wiki/Druid%E9%94%81%E7%9A%84%E5%85%AC%E5%B9%B3%E6%A8%A1%E5%BC%8F%E9%97%AE%E9%A2%98)
- [https://jmeter.apache.org/usermanual/component_reference.html#Aggregate_Report](https://jmeter.apache.org/usermanual/component_reference.html#Aggregate_Report)
