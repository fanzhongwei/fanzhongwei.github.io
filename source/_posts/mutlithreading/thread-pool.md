---
title: 线程池详解
date: 2019-04-08
tags: 
	- java
	- java多线程
	- ThreadPool
categories:
	- java多线程
---

所谓线程池通俗的理解就是有一个池子，里面存放着已经创建好的线程，当有任务提交给线程池执行时，池子中的 某个线程会主动执行该任务。如果池子中的线程数量不够应付数量众多的任务时，则需要自动扩充新的线程到池子中，但是该数量是有限的，就好比池塘的水界线一样。当任务比较少的时候，池子中的线程能够自动回收，释放 资源。为了能够异步地提交任务和缓存未被处理的任务，需要有一个任务队列。

![ALMKeg.png](https://s2.ax1x.com/2019/04/13/ALMKeg.png)

<!-- more -->

# 前言
线程的使用：
```java
    Thread thread = new Thread(()->{
        System.out.println("Hello World!");
    });
    thread.start();
```

缺点：

- 使用一次创建一次
- 使用之后销毁线程
- 同时创建大量线程可能导致系统资源耗尽

# 线程池
在面向对象编程中，创建和销毁对象是很费时间的，因为创建一个对象要获取内存资源或者其它更多资源。
在Java中虚拟机将试图跟踪每一个对象，以便能够在对象销毁后进行垃圾回收。所以提高服务程序效率的一个
手段就是尽可能减少创建和销毁对象的次数，特别是一些很耗资源的对象创建和销毁。
如何利用已有对象来服务就是一个解决的关键问题，这也就是"池化资源"技术产生的原因。


线程池是一种多线程处理形式，处理过程中将任务添加到队列，然后在创建线程后自动启动这些任务。

>线程是稀缺资源，使用线程池可以减少创建和销毁线程的次数，每个工作线程都可以重复使用。 
>
>可以根据系统的承受能力，调整线程池中工作线程的数量，防止因为消耗过多内存导致服务器崩溃。

一个线程池包括以下四个基本组成部分：
- 线程池管理器（ThreadPool）：用于创建并管理线程池，包括创建线程池、销毁线程池，添加新任务；
- 工作线程（PoolWorker）：线程池中线程，在没有任务时处于等待状态，可以循环的执行任务；
- 任务接口（Task）：每个任务必须实现的接口，以供工作线程调度任务的执行，它主要规定了任务的入口，任务执行完后的收尾工作，任务的执行状态等；
- 任务队列（taskQueue）：用于存放没有处理的任务。提供一种缓冲机制。

## 线程池的五种状态

> 线程池状态示意图以及五种状态的说明摘自CSDN一只逗比的程序猿

一共有五种，分别是RUNNING、SHUTDOWN、STOP、TIDYING、TERMINATED

线程池状态切换示意图

[![ALMO0g.md.png](https://s2.ax1x.com/2019/04/13/ALMO0g.md.png)](https://imgchr.com/i/ALMO0g)

- RUNNING
状态说明：线程池处在RUNNING状态时，能够接收新任务，以及对已添加的任务进行处理

状态切换：线程池的初始化状态是RUNNING。换句话说，线程池被一旦被创建，就处于RUNNING状态，并且线程池中的任务数为0

- SHUTDOWN
状态说明：线程池处在SHUTDOWN状态时，不接收新任务，但能处理已添加的任务

状态切换：调用线程池的shutdown()接口时，线程池由RUNNING -> SHUTDOWN

注：虽然状态已经不是RUNNING了，但是如果任务队列中还有任务的时候，线程池仍然会继续执行，具体分析请见ThreadPoolExecutor.execute()方法解析

- STOP
状态说明：线程池处在STOP状态时，不接收新任务，不处理已添加的任务，并且会中断正在处理的任务

状态切换：调用线程池的shutdownNow()接口时，线程池由(RUNNING or SHUTDOWN ) -> STOP

- TIDYING
状态说明：当所有的任务已终止，ctl记录的”任务数量”为0，线程池会变为TIDYING状态。当线程池变为TIDYING状态时，会执行钩子函数terminated()。terminated()在ThreadPoolExecutor类中是空的，若用户想在线程池变为TIDYING时，进行相应的处理；可以通过重载terminated()函数来实现

状态切换：当线程池在SHUTDOWN状态下，阻塞队列为空并且线程池中执行的任务也为空时，就会由 SHUTDOWN -> TIDYING。 当线程池在STOP状态下，线程池中执行的任务为空时，就会由STOP -> TIDYING

- TERMINATED
状态说明：线程池彻底终止，就变成TERMINATED状态

状态切换：线程池处在TIDYING状态时，执行完terminated()之后，就会由 TIDYING -> TERMINATED

线程池五种状态的二进制表示
| 线程池状态 | 二进制 |
| ---------- | ------ |
| RUNNING    | 111    |
| SHUTDOWN   | 000    |
| STOP       | 001    |
| TIDYING    | 010    |
| TERMINATED | 011    |

```
COUNT_BITS :29
RUNNING    :11100000 00000000 00000000 00000000
SHUTDOWN   :00000000 00000000 00000000 00000000
STOP       :00100000 00000000 00000000 00000000
TIDYING    :01000000 00000000 00000000 00000000
TERMINATED :01100000 00000000 00000000 00000000
RUNNING    :-536870912
SHUTDOWN   :0
STOP       :536870912
TIDYING    :1073741824
TERMINATED :1610612736
```


## 工作线程（PoolWorker）
工作线程是由ThreadPoolExecutor的内部类Worker类实现：
```java
    /**
     * Class Worker mainly maintains interrupt control state for
     * threads running tasks, along with other minor bookkeeping.
     * This class opportunistically extends AbstractQueuedSynchronizer
     * to simplify acquiring and releasing a lock surrounding each
     * task execution.  This protects against interrupts that are
     * intended to wake up a worker thread waiting for a task from
     * instead interrupting a task being run.  We implement a simple
     * non-reentrant mutual exclusion lock rather than use
     * ReentrantLock because we do not want worker tasks to be able to
     * reacquire the lock when they invoke pool control methods like
     * setCorePoolSize.  Additionally, to suppress interrupts until
     * the thread actually starts running tasks, we initialize lock
     * state to a negative value, and clear it upon start (in
     * runWorker).
     */
    private final class Worker
        extends AbstractQueuedSynchronizer
        implements Runnable
    {
        /** Thread this worker is running in.  Null if factory fails. */
        final Thread thread;
        /** Initial task to run.  Possibly null. */
        Runnable firstTask;
        
        /**
         * Creates with given first task and thread from ThreadFactory.
         * @param firstTask the first task (null if none)
         */
        Worker(Runnable firstTask) {
            setState(-1); // inhibit interrupts until runWorker
            this.firstTask = firstTask;
            this.thread = getThreadFactory().newThread(this);
        }
        
        /** Delegates main run loop to outer runWorker  */
        public void run() {
            runWorker(this);
        }
    }
```
Worker是实现了Runnable接口，每个Worker中有一个线程属性`thread`,添加Worker的时候会启动该线程，该线程会循环执行任务，直到线程池停止。

## 任务接口（Task）
- Runnable
```java
public interface Runnable {
    /**
     * When an object implementing interface <code>Runnable</code> is used
     * to create a thread, starting the thread causes the object's
     * <code>run</code> method to be called in that separately executing
     * thread.
     * <p>
     * The general contract of the method <code>run</code> is that it may
     * take any action whatsoever.
     *
     * @see     java.lang.Thread#run()
     */
    public abstract void run();
}
```
任务需要实现Runnable接口，实现抽象方法`run`,在其中编写具体的任务实现。
- Callable
```java
public interface Callable<V> {
    /**
     * Computes a result, or throws an exception if unable to do so.
     *
     * @return computed result
     * @throws Exception if unable to compute a result
     */
    V call() throws Exception;
}
```
任务实现Callable接口，实现抽象方法`call`，这个方法有一个返回值，用于获取任务执行的结果。

提交到线程池后，会返回另一个实现了Runnable接口的`RunnableFuture`,其定义如下：
```java
public interface RunnableFuture<V> extends Runnable, Future<V> {
    /**
     * Sets this Future to the result of its computation
     * unless it has been cancelled.
     */
    void run();
}
```
`RunnableFuture`接口继承了`Runnable`接口和`Future`接口，可以调用提交到线程池后返回的`RunnableFuture`的`get`方法，该方法是阻塞的，直到该任务执行完成。
```java
    public V get() throws InterruptedException, ExecutionException {
        int s = state;
        if (s <= COMPLETING)
            s = awaitDone(false, 0L);
        return report(s);
    }
```

## 任务队列

任务提交到线程池后，如果没有空闲的线程来执行该任务，则会将其放到任务缓冲队列里面，该队列是一个阻塞队列：
```java
private final BlockingQueue<Runnable> workQueue;
```
`BlockingQueue`4 组不同的方法用于插入、移除以及对队列中的元素进行检查。如果请求的操作不能得到立即执行的话，每个方法的表现也不同。这些方法如下：

|          | *抛出异常*  | *特殊值*   | *阻塞*   | *超时*                 |
| -------- | ----------- | ---------- | -------- | ---------------------- |
| **插入** | `add(e)`    | `offer(e)` | `put(e)` | `offer(e, time, unit)` |
| **移除** | `remove()`  | `poll()`   | `take()` | `poll(time, unit)`     |
| **检查** | `element()` | `peek()`   | *不可用* | *不可用*               |


四组不同的行为方式解释:

- 异常

如果试图的操作无法立即执行，抛一个异常。

- 特定值

如果试图的操作无法立即执行，返回一个特定的值(常常是 true / false)。

- 阻塞

如果试图的操作无法立即执行，该方法调用将会发生阻塞，直到能够执行。

- 超时

如果试图的操作无法立即执行，该方法调用将会发生阻塞，直到能够执行，但等待时间不会超过给定值。返回一个特定值以告知该操作是否成功(典型的是 true / false)。


具有以下特点：
- 先进先出（FIFO）
- 不接受 null 元素
- 可以是限定容量的
- 实现主要用于生产者-使用者队列，但它另外还支持 Collection 接口
- 实现是线程安全的

`BlockingQueue`有多种实现，分别满足不同功能的线程池，这里只介绍线程池中常用的队列（其它实现有兴趣的可以深入具体学习）：
- ArrayBlockingQueue 

一个由数组支持的有界阻塞队列。此队列按 FIFO（先进先出）原则对元素进行排序。队列的头部是在队列中存在时间最长的元素。队列的尾部 是在队列中存在时间最短的元素。新元素插入到队列的尾部，队列获取操作则是从队列头部开始获得元素。

- DelayQueue

Delayed 元素的一个无界阻塞队列，只有在延迟期满时才能从中提取元素。该队列的头部 是延迟期满后保存时间最长的 Delayed 元素。如果延迟都还没有期满，则队列没有头部，并且 poll 将返回 null。当一个元素的 getDelay(TimeUnit.NANOSECONDS) 方法返回一个小于等于 0 的值时，将发生到期。即使无法使用 take 或 poll 移除未到期的元素，也不会将这些元素作为正常元素对待。

- LinkedBlockingQueue

内部以一个链式结构(链接节点)对其元素进行存储，满足FIFO(先进先出)原则。

- SynchronousQueue

SynchronousQueue 是一个特殊的队列，它的内部同时只能够容纳单个元素。如果该队列已有一元素的话，试图向队列中插入一个新元素的线程将会阻塞，直到另一个线程将该元素从队列中抽走。同样，如果该队列为空，试图向队列中抽取一个元素的线程将会阻塞，直到另一个线程向队列中插入了一条新的元素。


## 线程池管理器
### 类图
![AZCAdH.png](https://s2.ax1x.com/2019/03/16/AZCAdH.png)

- Executor：负责线程的使用与调度的根接口
- ExecutorService：Executor的子接口，线程池的主要接口
- AbstractExecutorService：实现了ExecutorService接口，基本实现了ExecutorService其中声明的所有方法，另有添加其他方法
- ThreadPoolExecutor：继承了AbstractExecutorService，线程池常用实现类
- ScheduledExecutorService：继承了ExecutorService，负责线程调度的接口
- ScheduledThreadPoolExecutor：继承了ThreadPoolExecutor同时实现了ScheduledExecutorService


### Executors
Executors利用工厂模式向我们提供了4种线程池实现方式：

- newSingleThreadExecutor

创建一个单线程的线程池。这个线程池只有一个线程在工作，也就是相当于单线程串行执行所有任务。如果这个唯一的线程因为异常结束，那么会有一个新的线程来替代它。
此线程池保证所有任务的执行顺序按照任务的提交顺序执行。
> 拥有一个存活时间无限长的线程，排队的任务将放入无界队列，适用于一个任务一个任务执行的场景。

- newFixedThreadPool

创建固定大小的线程池。每次提交一个任务就创建一个线程，直到线程达到线程池的最大大小。
线程池的大小一旦达到最大值就会保持不变，如果某个线程因为执行异常而结束，那么线程池会补充一个新线程。
> 每个线程存活的时间无限，适用于执行长期的任务，例如服务器。

- newCachedThreadPool

创建一个可缓存的线程池。如果线程池的大小超过了处理任务所需要的线程，
那么就会回收部分空闲（60秒不执行任务）的线程，当任务数增加时，此线程池又可以智能的添加新线程来处理任务。
此线程池不会对线程池大小做限制，线程池大小完全依赖于操作系统（或者说JVM）能够创建的最大线程大小。
> 可以无限增加线程数，适用于执行很多短期异步的小程序或者负载较轻的服务器。

- newScheduledThreadPool

创建一个定长线程池，支持定时及周期性任务执行.

!> 阿里巴巴编码规约有一条：

!> 【强制】线程池不允许使用 Executors 去创建，而是通过 ThreadPoolExecutor 的方式，这样的处理方式让写的同学更加明确线程池的运行规则，规避资源耗尽的风险。

大家对线程池的了解吗，`newSingleThreadExecutor`、`newFixedThreadPool`、`newCachedThreadPool`、`newScheduledThreadPool`

- 这些线程池是如何实现的呢？
- 创建的时候都有哪些参数呢？

### ThreadPoolExecutor

#### 构造函数

 先来看一下ThreadPoolExecutor的构造函数吧。

![AZHzp4.png](https://s2.ax1x.com/2019/03/17/AZHzp4.png)

在这里着重介绍几个参数

- 阻塞队列

没有空闲的Worker时，将到达的任务加入队列中。

    1.直接传递。SynchronousQueue队列的默认方式，一个存储元素的阻塞队列而是直接投递到线程中。
    每一个入队操作必须等到另一个线程调用移除操作，否则入队将一直阻塞。
    当处理一些可能有内部依赖的任务时，这种策略避免了加锁操作。
    直接传递一般不能限制maximumPoolSizes以避免拒绝 接收新的任务。
    如果新增任务的速度大于任务处理的速度就会造成增加无限多的线程的可能性。
        
    2.无界队列。如LinkedBlockingQueue，当核心线程正在工作时，使用不用预先定义大小的无界队列将使新到来的任务处理等到中，
    所以如果线程数是小于corePoolSize时，将不会创建有入队操作。这种策略将很适合那些相互独立的任务，
    如Web服务器。如果新增任务的速度大于任务处理的速度就会造成无界队列一直增长的可能性。
        
    3.有界队列。如ArrayBlockingQueue，当定义了maximumPoolSizes时使用有界队列可以预防资源的耗尽，
    但是增加了调整和控制队列的难度，队列的大小和线程池的大小是相互影响的，
    使用很大的队列和较小的线程池会减少CPU消耗、操作系统资源以及线程上下文开销，但却人为的降低了吞吐量。
    如果任务是频繁阻塞型的（I/O），系统是可以把时间片分给多个线程的。而采用较小的队列和较大的线程池，
    虽会造成CPU繁忙，但却会遇到调度开销，这也会降低吞吐量。

- 饱和策略（拒绝接收任务）

当Executor调用shutdown方法后或者达到工作队列的最容量时,线程池则已经饱和了，此时则不会接收新的task。但无论是何种情 况，execute方法会调用RejectedExecutionHandler#rejectedExecution方法来执行饱和策略，在线程池内部预定义了几种处理策略：

    1.终止执行(AbortPolicy)。默认策略， Executor会抛出一个RejectedExecutionException运行异常到调用者线程来完成终止。
    
    2.调用者线程来运行任务(CallerRunsPolicy)。这种策略会由调用execute方法的线程自身来执行任务，
    它提供了一个简单的反馈机制并能降低新任务的提交频率。
    
    3.丢弃策略(DiscardPolicy)。不处理，直接丢弃提交的任务。
    
    4.丢弃队列里最近的一个任务(DiscardOldestPolicy)。如果Executor还未shutdown的话，
    则丢弃工作队列的最近的一个任务，然后执行当前任务。


#### 主要属性

```java
    /**
     * The queue used for holding tasks and handing off to worker
     * threads.  We do not require that workQueue.poll() returning
     * null necessarily means that workQueue.isEmpty(), so rely
     * solely on isEmpty to see if the queue is empty (which we must
     * do for example when deciding whether to transition from
     * SHUTDOWN to TIDYING).  This accommodates special-purpose
     * queues such as DelayQueues for which poll() is allowed to
     * return null even if it may later return non-null when delays
     * expire.
     */
    private final BlockingQueue<Runnable> workQueue;
    
    /**
     * Lock held on access to workers set and related bookkeeping.
     * While we could use a concurrent set of some sort, it turns out
     * to be generally preferable to use a lock. Among the reasons is
     * that this serializes interruptIdleWorkers, which avoids
     * unnecessary interrupt storms, especially during shutdown.
     * Otherwise exiting threads would concurrently interrupt those
     * that have not yet interrupted. It also simplifies some of the
     * associated statistics bookkeeping of largestPoolSize etc. We
     * also hold mainLock on shutdown and shutdownNow, for the sake of
     * ensuring workers set is stable while separately checking
     * permission to interrupt and actually interrupting.
     */
    private final ReentrantLock mainLock = new ReentrantLock();
    
    /**
     * Set containing all worker threads in pool. Accessed only when
     * holding mainLock.
     */
    private final HashSet<Worker> workers = new HashSet<Worker>();

    /**
     * Factory for new threads. All threads are created using this
     * factory (via method addWorker).  All callers must be prepared
     * for addWorker to fail, which may reflect a system or user's
     * policy limiting the number of threads.  Even though it is not
     * treated as an error, failure to create threads may result in
     * new tasks being rejected or existing ones remaining stuck in
     * the queue.
     *
     * We go further and preserve pool invariants even in the face of
     * errors such as OutOfMemoryError, that might be thrown while
     * trying to create threads.  Such errors are rather common due to
     * the need to allocate a native stack in Thread.start, and users
     * will want to perform clean pool shutdown to clean up.  There
     * will likely be enough memory available for the cleanup code to
     * complete without encountering yet another OutOfMemoryError.
     */
    private volatile ThreadFactory threadFactory;
    
    /**
     * Handler called when saturated or shutdown in execute.
     */
    private volatile RejectedExecutionHandler handler;

    /**
     * Timeout in nanoseconds for idle threads waiting for work.
     * Threads use this timeout when there are more than corePoolSize
     * present or if allowCoreThreadTimeOut. Otherwise they wait
     * forever for new work.
     */
    private volatile long keepAliveTime;
    
    /**
     * Core pool size is the minimum number of workers to keep alive
     * (and not allow to time out etc) unless allowCoreThreadTimeOut
     * is set, in which case the minimum is zero.
     */
    private volatile int corePoolSize;
    
    /**
     * Maximum pool size. Note that the actual maximum is internally
     * bounded by CAPACITY.
     */
    private volatile int maximumPoolSize;
```

#### 任务的执行

线程池执行任务的主要方法有：`execute`、`submit`，其中submit方法会将传入的Runnable或者Callable封装成RunnableFuture然后调用execute方法，
那么任务具体是如何执行的呢？我的理解大致如下：
![A8ofeS.png](https://s2.ax1x.com/2019/03/22/A8ofeS.png)

其代码如下：
```java
    public void execute(Runnable command) {
        if (command == null)
            throw new NullPointerException();
        /*
         * Proceed in 3 steps:
         *
         * 1. If fewer than corePoolSize threads are running, try to
         * start a new thread with the given command as its first
         * task.  The call to addWorker atomically checks runState and
         * workerCount, and so prevents false alarms that would add
         * threads when it shouldn't, by returning false.
         *
         * 2. If a task can be successfully queued, then we still need
         * to double-check whether we should have added a thread
         * (because existing ones died since last checking) or that
         * the pool shut down since entry into this method. So we
         * recheck state and if necessary roll back the enqueuing if
         * stopped, or start a new thread if there are none.
         *
         * 3. If we cannot queue task, then we try to add a new
         * thread.  If it fails, we know we are shut down or saturated
         * and so reject the task.
         */
        int c = ctl.get();
        if (workerCountOf(c) < corePoolSize) {
            if (addWorker(command, true))
                return;
            c = ctl.get();
        }
        if (isRunning(c) && workQueue.offer(command)) {
            int recheck = ctl.get();
            if (! isRunning(recheck) && remove(command))
                reject(command);
            else if (workerCountOf(recheck) == 0)
                addWorker(null, false);
        }
        else if (!addWorker(command, false))
            reject(command);
    }
```
execute方法简单总结如下：

- 如果当前线程池里面运行的线程数量小于corePoolSize，则创建新的线程（需要获取全局锁）。
- 如果当前线程池里面运行的线程数量大于或等于corePoolSize，则将任务加入workQueue中，缓存起来。
- 如果workQueue已满，但是线程数量小于maximumPoolSize，则继续添加线程（需要再次获取全局锁）。
- 如果线程数已达到最大线程数了，任务队列也满了，任务将被拒绝，并调用RejectedExecutionHandler的rejectExecution方法。

#### 添加工作线程addWorker

```java
// 两个参数，firstTask表示需要跑的任务。boolean类型的core参数为true的话表示使用corePoolSize，为false使用maximumPoolSize
// 返回值是boolean类型，true表示新任务被添加了，并且执行了。否则是false
private boolean addWorker(Runnable firstTask, boolean core) {
    retry:
    for (;;) {
        int c = ctl.get();
        int rs = runStateOf(c); // 线程池当前状态

        // 这个判断转换成 rs >= SHUTDOWN && (rs != SHUTDOWN || firstTask != null || workQueue.isEmpty)。 
        // 概括为3个条件：
        // 1. 线程池不在RUNNING状态并且状态是STOP、TIDYING或TERMINATED中的任意一种状态

        // 2. 线程池不在RUNNING状态，线程池接受了新的任务 

        // 3. 线程池不在RUNNING状态，阻塞队列为空。  满足这3个条件中的任意一个的话，拒绝执行任务

        if (rs >= SHUTDOWN &&
            ! (rs == SHUTDOWN &&
               firstTask == null &&
               ! workQueue.isEmpty()))
            return false;

        for (;;) {
            int wc = workerCountOf(c); // 线程池线程个数
            // 如果线程池线程数量超过线程池最大容量或者线程数量超过了
            // corePoolSize(core参数为true，core参数为false的话判断超过最大大小)
            if (wc >= CAPACITY ||
                wc >= (core ? corePoolSize : maximumPoolSize)) 
                return false; // 超过直接返回false
            if (compareAndIncrementWorkerCount(c)) // 没有超过各种大小的话，cas操作线程池线程数量+1，cas成功的话跳出循环
                break retry;
            c = ctl.get();  // 重新检查状态
            if (runStateOf(c) != rs) // 如果状态改变了，重新循环操作
                continue retry;
            // else CAS failed due to workerCount change; retry inner loop
        }
    }
    // 走到这一步说明cas操作成功了，线程池线程数量+1
    boolean workerStarted = false;
    boolean workerAdded = false;
    Worker w = null;
    try {
        final ReentrantLock mainLock = this.mainLock;
        w = new Worker(firstTask); // 基于任务firstTask构造worker
        final Thread t = w.thread; // 使用Worker的属性thread，这个thread是使用ThreadFactory构造出来的
        if (t != null) { // ThreadFactory构造出的Thread有可能是null，做个判断
            mainLock.lock();  // 得到线程池的可重入锁
            try {
                // 在锁住之后再重新检测一下状态
                int c = ctl.get();
                int rs = runStateOf(c);
                // 如果线程池在RUNNING状态或者线程池在SHUTDOWN状态并且任务是个null
                if (rs < SHUTDOWN ||
                    (rs == SHUTDOWN && firstTask == null)) { 
                    if (t.isAlive()) // 判断线程是否还活着，也就是说线程已经启动并且还没死掉
                        throw new IllegalThreadStateException(); // 如果存在已经启动并且还没死的线程，抛出异常
                    workers.add(w); // worker添加到线程池的workers属性中，是个HashSet
                    int s = workers.size(); // 得到目前线程池中的线程个数
                    // 如果线程池中的线程个数超过了线程池中的最大线程数时，更新一下这个最大线程数
                    if (s > largestPoolSize) 
                        largestPoolSize = s;
                    workerAdded = true; // 标识一下Worker已经添加成功
                }
            } finally {
                mainLock.unlock(); // 解锁
            }
            if (workerAdded) { // 如果Worker添加成功，运行任务
                t.start(); // 启动线程，启动Worker
                workerStarted = true;
            }
        }
    } finally {
        if (! workerStarted) // 如果任务启动失败，调用addWorkerFailed方法
            addWorkerFailed(w);
    }
    return workerStarted;
}
```
工作线程添加的方法基本了解了，那么这个Worker是如何运行的呢，又是如何重用，如何执行多个任务的呢？

#### 工作线程的运行

Worker在addWorker方法中，当Worker成功添加到workers后，调用Worker.thread启动Worker，在前面[Worker的介绍](#工作线程（PoolWorker）)中了解到run方法直接调用了
ThreadPoolExecutor.runWorker方法具体执行任务，ThreadPoolExecutor.runWorker代码如下：

```java
final void runWorker(Worker w) {
    Thread wt = Thread.currentThread(); // 得到当前线程
    Runnable task = w.firstTask; // 得到Worker中的任务task，也就是用户传入的task
    w.firstTask = null; // 将Worker中的任务置空
    w.unlock(); // allow interrupts。 
    boolean completedAbruptly = true; // 标识当前Worker异常结束，默认是异常结束
    try {
        // 如果worker中的任务不为空，执行执行任务
        // 否则使用getTask获得任务。一直循环，除非得到的任务为空才退出
        while (task != null || (task = getTask()) != null) {
            // 如果拿到了任务，给自己上锁，表示当前Worker已经要开始执行任务了，
            // 已经不是处于闲置Worker(闲置Worker的解释请看下面的线程池关闭)
            w.lock();  
            // 在执行任务之前先做一些处理。 
            // 1. 如果线程池已经处于STOP状态并且当前线程没有被中断，中断线程 
            // 2. 如果线程池还处于RUNNING或SHUTDOWN状态，并且当前线程已经被中断了，
            // 重新检查一下线程池状态，如果处于STOP状态并且没有被中断，那么中断线程
            if ((runStateAtLeast(ctl.get(), STOP) ||
                 (Thread.interrupted() &&
                  runStateAtLeast(ctl.get(), STOP))) &&
                !wt.isInterrupted())
                wt.interrupt();
            try {
                // 任务执行前需要做什么，ThreadPoolExecutor是个空实现，子类可以自行扩展
                beforeExecute(wt, task); 
                Throwable thrown = null;
                try {
                    // 真正的开始执行任务，这里run的时候可能会被中断，比如线程池调用了shutdownNow方法
                    task.run(); 
                } catch (RuntimeException x) { // 任务执行发生的异常全部抛出，不在runWorker中处理
                    thrown = x; throw x;
                } catch (Error x) {
                    thrown = x; throw x;
                } catch (Throwable x) {
                    thrown = x; throw new Error(x);
                } finally {
                    // 任务执行结束需要做什么，ThreadPoolExecutor是个空实现，子类可以自行扩展
                    afterExecute(task, thrown); 
                }
            } finally {
                task = null;
                w.completedTasks++; // 记录执行任务的个数
                w.unlock(); // 执行完任务之后，解锁，Worker变成闲置Worker，等待执行下一个任务
            }
        }
        completedAbruptly = false; // 正常结束
    } finally {
        processWorkerExit(w, completedAbruptly); // Worker退出时执行
    }
}
```

Worker正常结束或者异常结束时都会调用processWorkerExit方法，当Worker异常结束时（比如执行的任务中抛出了未处理的异常）可能会重新创建一个新的Worker替换上。
processWorkerExit具体实现如下：
```java
private void processWorkerExit(Worker w, boolean completedAbruptly) {
    // 如果Worker没有正常结束流程调用processWorkerExit方法，worker数量减一。
    // 如果是正常结束的话，在getTask方法里worker数量已经减一了
    if (completedAbruptly) 
        decrementWorkerCount();

    final ReentrantLock mainLock = this.mainLock;
    mainLock.lock(); // 加锁，防止并发问题
    try {
        completedTaskCount += w.completedTasks; // 记录总的完成任务数
        workers.remove(w); // 线程池的worker集合删除掉需要回收的Worker
    } finally {
        mainLock.unlock(); // 解锁
    }

    tryTerminate(); // 尝试结束线程池

    int c = ctl.get();
    if (runStateLessThan(c, STOP)) {  // 如果线程池还未停止，处于RUNNING或者SHUTDOWN状态
        if (!completedAbruptly) { // Worker是正常结束流程的话
            int min = allowCoreThreadTimeOut ? 0 : corePoolSize; // 核心线程允许超过空闲时间回收
            if (min == 0 && ! workQueue.isEmpty())
                min = 1;
            if (workerCountOf(c) >= min) // 还有在工作的Worker
                return; // 不需要新开一个Worker
        }
        // 新开一个Worker代替原先的Worker
        // 新开一个Worker有以下几种情况
        // 1. 用户执行的任务发生了异常
        // 2. Worker正常退出，Worker数量比线程池corePoolSize小，阻塞队列不空但是没有任何Worker在工作
        addWorker(null, false);
    }
}
```

#### 线程池的关闭

shutdown方法，关闭线程池，关闭之后阻塞队列里的任务不受影响，会继续被Worker处理，但是新的任务不会被接受，方法实现如下：
```java
public void shutdown() {
    final ReentrantLock mainLock = this.mainLock;
    mainLock.lock(); // 关闭的时候需要加锁，防止并发
    try {
        checkShutdownAccess(); // 检查关闭线程池的权限
        advanceRunState(SHUTDOWN); // 把线程池状态更新到SHUTDOWN
        interruptIdleWorkers(); // 中断闲置的Worker
        onShutdown(); // 钩子方法，默认不处理。ScheduledThreadPoolExecutor会做一些处理
    } finally {
        mainLock.unlock(); // 解锁
    }
    tryTerminate(); // 尝试结束线程池
}
```

interruptIdleWorkers方法，注意，这个方法打断的是闲置Worker，打断闲置Worker之后，getTask方法会返回null，然后Worker会被回收。那什么是闲置Worker呢？

闲置Worker是这样解释的：Worker运行的时候会去阻塞队列拿数据(getTask方法)，拿的时候如果没有设置超时时间，那么会一直阻塞等待阻塞队列进数据，这样的Worker就被称为闲置Worker。
由于Worker也是一个AQS(AbstractQueuedSynchronizer,详解点击[这里](https://www.jianshu.com/p/da9d051dcc3d))，在runWorker方法里会有一对lock和unlock操作，这对lock操作是为了确保Worker不是一个闲置Worker。

所以Worker被设计成一个AQS是为了根据Worker的锁来判断是否是闲置线程，是否可以被强制中断。我们来看看它的实现：
```java
// 调用他的一个重载方法，传入了参数false，表示要中断所有的正在运行的闲置Worker，如果为true表示只打断一个闲置Worker
private void interruptIdleWorkers() {
    interruptIdleWorkers(false);
}

private void interruptIdleWorkers(boolean onlyOne) {
    final ReentrantLock mainLock = this.mainLock;
    mainLock.lock(); // 中断闲置Worker需要加锁，防止并发
    try {
        for (Worker w : workers) { 
            Thread t = w.thread; // 拿到worker中的线程
            // Worker中的线程没有被打断并且Worker可以获取锁，这里Worker能获取锁说明Worker是个闲置Worker，
            // 在阻塞队列里拿数据一直被阻塞，没有数据进来。如果没有获取到Worker锁，说明Worker还在执行任务，
            // 不进行中断(shutdown方法不会中断正在执行的任务)
            if (!t.isInterrupted() && w.tryLock()) { 
                try {
                    t.interrupt();  // 中断Worker线程
                } catch (SecurityException ignore) {
                } finally {
                    w.unlock(); // 释放Worker锁
                }
            }
            if (onlyOne) // 如果只打断1个Worker的话，直接break退出，否则，遍历所有的Worker
                break;
        }
    } finally {
        mainLock.unlock(); // 解锁
    }
}
```

从上面的代码可以看到，shutdown并不会立即停止线程池（shutdownNow会立即停止线程池），而是先将线程状态置于SHUTDOWN，然后中断闲置的Worker。
然后尝试结束线程池，tryTerminate的实现如下：
```java
final void tryTerminate() {
    for (;;) {
        int c = ctl.get();
        // 满足3个条件中的任意一个，不终止线程池
        // 1. 线程池还在运行，不能终止
        // 2. 线程池处于TIDYING或TERMINATED状态，说明已经在关闭了，不允许继续处理
        // 3. 线程池处于SHUTDOWN状态并且阻塞队列不为空，这时候还需要处理阻塞队列的任务，不能终止线程池
        if (isRunning(c) ||
            runStateAtLeast(c, TIDYING) ||
            (runStateOf(c) == SHUTDOWN && ! workQueue.isEmpty()))
            return;
        // 走到这一步说明线程池已经不在运行，阻塞队列已经没有任务，但是还要回收正在工作的Worker
        if (workerCountOf(c) != 0) {
             // 由于线程池不运行了，调用了线程池的关闭方法
             // 中断闲置Worker，直到回收全部的Worker。这里没有那么暴力，只中断一个，中断之后退出方法，
             // 中断了Worker之后，Worker会回收，然后还是会调用tryTerminate方法，如果还有闲置线程，那么继续中断
            interruptIdleWorkers(ONLY_ONE); 
            return;
        }
        // 走到这里说明worker已经全部回收了，并且线程池已经不在运行，阻塞队列已经没有任务。可以准备结束线程池了
        final ReentrantLock mainLock = this.mainLock;
        mainLock.lock(); // 加锁，防止并发
        try {
            if (ctl.compareAndSet(c, ctlOf(TIDYING, 0))) { // cas操作，将线程池状态改成TIDYING
                try {
                    terminated(); // 调用terminated方法
                } finally {
                    ctl.set(ctlOf(TERMINATED, 0)); // terminated方法调用完毕之后，状态变为TERMINATED
                    termination.signalAll();
                }
                return;
            }
        } finally {
            mainLock.unlock(); // 解锁
        }
        // else retry on failed CAS
    }
}
```
## 简单实战
好了关于线程池的简单介绍就到这里了，我们接下来看一个小小的例子，顺便了解一下线程池的参数选择。

线程数的选择常见策略如下：

- CPU密集型任务

尽量使用较小的线程池，一般为CPU核心数+1。
因为CPU密集型任务使得CPU使用率很高，若开过多的线程数，只能增加上下文切换的次数，因此会带来额外的开销。

- IO密集型任务

可以使用稍大的线程池，一般为2*CPU核心数。
IO密集型任务CPU使用率并不高，因此可以让CPU在等待IO的时候去处理别的任务，充分利用CPU时间。

- 混合型任务

可以将任务分成IO密集型和CPU密集型任务，然后分别用不同的线程池去处理。
只要分完之后两个任务的执行时间相差不大，那么就会比串行执行来的高效。
因为如果划分之后两个任务执行时间相差甚远，那么先执行完的任务就要等后执行完的任务，最终的时间仍然取决于后执行完的任务，而且还要加上任务拆分与合并的开销，得不偿失。

通过前面了解到ThreadPoolExecutor的[饱和策略](#构造函数)默认选择的是AbortPolicy策略，新来的任务将被丢弃，即使保证任务不丢弃的策略CallerRunsPolicy也是直接调用任务的run方法来实现。

我们如何实现一个满足生产者消费者模型的线程池呢，这里将Worker当做消费者，可以同时处理多个生产者提交的任务，同时要保证生产者过多时任务不被丢弃。具体代码如下：

```java
/**
 * package com.teddy.thread
 * description: 线程池工具类
 * Copyright 2018 Teddy, Inc. All rights reserved.
 *
 * @author Teddy
 * @date 2018-9-16 14:20
 */
public class ThreadPoolUtils {
    /**
     * 任务等待队列 容量
     */
    private static final int TASK_QUEUE_SIZE = 1000;
    /**
     * 空闲线程存活时间 单位分钟
     */
    private static final long KEEP_ALIVE_TIME = 10L;

    /**
     * 任务执行线程池
     */
    private static ThreadPoolExecutor threadPool;

    static {
        int corePoolNum = 2 * Runtime.getRuntime().availableProcessors() + 1;
        int maximumPoolSize = 2 * corePoolNum;
        threadPool = new ThreadPoolExecutor(
                corePoolNum,
                maximumPoolSize,
                KEEP_ALIVE_TIME,
                TimeUnit.MINUTES,
                new ArrayBlockingQueue<>(TASK_QUEUE_SIZE),
                new ThreadFactoryBuilder().setNameFormat("ThreadPoolUtils-%d").build(), (r, executor) -> {
            if (!executor.isShutdown()) {
                try {
                    executor.getQueue().put(r);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                    Thread.currentThread().interrupt();
                }
            }
        });
    }

    /**
     * Description: 执行任务
     *
     * @param task 任务
     * @author teddy
     * @date 2018/9/16
     */
    public static void execute(Runnable task) {
        threadPool.execute(task);
    }

    /**
     * Description: 提交任务到线程池
     *
     * @param task 任务
     *
     * @return Future<T>
     * @author teddy
     * @date 2019/3/23
     */
    public static <T> Future<T> submit(Callable<T> task){
        return threadPool.submit(task);
    }
}
```