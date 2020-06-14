---
title: 多线程编程--并发包
date: 2020-05-11
tags: 
	- java
	- java多线程
	- 多线程编程
	- 线程安全
	- JUC 常用类
categories:
	- java多线程
---

之前我们了解了线程的基础知识，那么多个线程一起运行的时候，难免会操作同一个资源。从上一讲里面我们了解到每个线程会有自己的缓存，那么多个线程操作同一个资源的时候，怎么保证资源操作结果的正确性。这些问题，其实从JDK1.5起已经提供了解决方案，接下来就让我们一起来看看`java.util.concurrent`。

![java并发包](https://10.url.cn/qqcourse_logo_ng/ajNVdqHZLLDpfiageJ021AspmrAdS6FlCPC7JgO4Zgjp5ozCFiaZRJguDIEWicUBnfG9f5bxFdbQcY/)

<!-- more -->

首先我们来看一个经典问题：i++是否线程安全？

```java
    static class AddTest{
        volatile static int i;
        static void unsafeAddCount(){
            i++;
        }
    }

	@Test
    public void unsafeAddCountTest() throws InterruptedException {
        for (int i = 0; i < 100; i++) {
            Thread thread = new Thread(() -> AddTest.unsafeAddCount());
            thread.start();
        }
        Thread.sleep(1000);
        System.out.println("i = " + AddTest.i);
    }
```

运行结果i会是多少呢，有可能：`i = 98`、`i = 99`、`i = 100`，为什么会出现这样的结果呢？

 volatile只能保证可见性，并不能保证原子性，表达式i++操作步骤分解如下：

> 1、从主存取出i的值放到线程栈<br/>
> 2、在线程栈中计算i+1的值<br/>
> 3、将i+1的值写到主存中的变量i<br/>

 很不幸的是，这几个操作并不是原子性的，如果多个同时进行i++操作，就会出现线程安全问题。<br/>

> 1、获取--> 线程A：i=1，线程B：i=1<br/>
> 2、计算--> 线程A：i+1=2，线程B：i+1=2<br/>
> 3、回写--> 线程A：i=2，线程B：i=2<br/>

# 原子类（Atomic）

要保证i++的线程安全，加上`synchronized`关键字即可：

```java
    static class AddTest{
        volatile static int i;
        synchronized static void safeAddCount(){
            i++;
        }
    }

    @Test
    public void safeAddCountTest() throws InterruptedException {
        for (int i = 0; i < 100; i++) {
            Thread thread = new Thread(() -> AddTest.safeAddCount());
            thread.start();
        }
        Thread.sleep(1000);
        System.out.println("i = " + AddTest.i);
    }
```

这下不管运行多少次i的结果都是100，不信的可以尝试一下。

在`java.util.concurrent.atomic`提供了原子类，解决i++也可以使用`AtomicInteger`，如下所示：

```java
    @Test
    public void atomicIntegerSafeTest() throws InterruptedException {
        AtomicInteger i = new AtomicInteger();
        for (int j = 0; j < 100; j++) {
            Thread thread = new Thread(() -> i.getAndIncrement());
            thread.start();
        }
        Thread.sleep(1000);
        System.out.println("i = " + i.get());
    }
```

那么`AtomicInteger`是怎么保证线程安全的呢，让我们看看`getAndIncrement`方法，：

```java
    public final int getAndIncrement() {
        return unsafe.getAndAddInt(this, valueOffset, 1);
    }
	public final int getAndAddInt(Object var1, long var2, int var4) {
        int var5;
        do {
            //获取对象内存地址偏移量上的数值v
            var5 = this.getIntVolatile(var1, var2);
        } while(!this.compareAndSwapInt(var1, var2, var5, var5 + var4));

        return var5;
    }

/**
* 比较obj的offset处内存位置中的值和期望的值，如果相同则更新。此更新是不可中断的。
* 
* @param obj 需要更新的对象
* @param offset obj中整型field的偏移量
* @param expect 希望field中存在的值
* @param update 如果期望值expect与field的当前值相同，设置filed的值为这个新值
* @return 如果field的值被更改返回true
*/
public native boolean compareAndSwapInt(Object obj, long offset, int expect, int update);
```

> Unsafe类只能由jdk源码使用，否则会抛出异常：java.lang.SecurityException: Unsafe

jdk中提供的原子类如下：

- `AtomicBoolean` 保证布尔值的原子性

- `AtomicInteger` 保证整型的原子性

- `AtomicLong` 保证长整型的原子性

- `AtomicIntegerArray` 保证整型数组的原子性

- `AtomicLongArray` 保证长整型数组原子性

- `AtomicIntegerFieldUpdater` 保证整型的字段更新

- `AtomicLongFieldUpdater` 保证长整型的字段更新

- `AtomicReferenceArray` 保证引用数组的原子性

- `AtomicReferenceFieldUpdater` 保证引用类型的字段更新

- `AtomicStampedReference` 可以解决`CAS`的`ABA`问题，类似提供版本号

- `AtomicMarkableReference` 可以解决`CAS`的`ABA`问题，提供是或否进行判断

# 锁（Lock）

## 简单锁实现

上一讲我们讲到[线程间通信](https://fanzhongwei.com/mutlithreading/multithreading-base.html#线程间通信)，在这里我们实现一个简单的锁。

```java
    static class SimpleLock {
        private boolean isLocked = false;

        public synchronized void lock()
                throws InterruptedException {
            while (isLocked) {
                wait();
            }
            isLocked = true;
        }

        public synchronized void unlock() {
            isLocked = false;
            notify();
        }
    }

    private SimpleLock simpleLock = new SimpleLock();
    private int instanceNum;
    private void simpleLockTest(String username) {
        try {
            simpleLock.lock();
            if ("b".equals(username)) {
                instanceNum = 200;
                System.out.println("b set over!");
            } else {
                instanceNum = 100;
                System.out.println("a set over!");
                Thread.sleep(2000);
            }
            System.out.println(username + " num = " + instanceNum);
        } catch (InterruptedException e) {
            e.printStackTrace();
        } finally {
            simpleLock.unlock();
        }
    }

    @Test
    public void threadSetInstanceNumTest() throws InterruptedException {
        Thread threadA = new Thread(() -> simpleLockTest("a"));
        Thread threadB = new Thread(() -> simpleLockTest("b"));
        threadA.start();
        threadB.start();
        Thread.sleep(3000);
    }
```

> 这个锁存在什么问题呢，可重入？公平性？

## ReentrantLock

除了使用`synchronized`关键字保证线程安全之外，还能够使用`java.util.concurrent.locks`包中所提供的Lock，先来看一个简单的例子吧。

```java
    private int instanceNum;
    private Lock lock = new ReentrantLock();
    private void addInstanceNum(String username) {
        lock.lock();
        try {
            if ("b".equals(username)) {
                instanceNum = 200;
                System.out.println("b set over!");
            } else {
                instanceNum = 100;
                System.out.println("a set over!");
                Thread.sleep(2000);
            }
            System.out.println(username + " num = " + instanceNum);
        } catch (InterruptedException e) {
            e.printStackTrace();
        } finally {
            lock.unlock();
        }
    }

    @Test
    public void threadSetInstanceNumTest() throws InterruptedException {
        Thread threadA = new Thread(() -> addInstanceNum("a"));
        Thread threadB = new Thread(() -> addInstanceNum("b"));
        threadA.start();
        threadB.start();
        Thread.sleep(3000);
    }
```

不加lock的时候输出：

```
a set num is 100!
b set num is 200!
b num = 200
a num = 200	// 这里出现了线程安全问题，a线程设置的值被b线程设置的值覆盖了。
```

加上lock之后，只有等一个线程执行完之后，另一个线程才能进入：

```
a set num is 100!
a num = 100
b set num is 200!
b num = 200
```

## ReentrantReadWriteLock

如果我们对资源的读取比较频繁，而修改相对较少，使用前面提到的锁有什么弊端呢，两个线程同时读取资源需要加锁吗？

ReadWriteLock就是读写锁，它是一个接口，ReentrantReadWriteLock实现了这个接口。可以通过readLock()获取读锁，只要没有线程拥有写锁（writers==0），且没有线程在请求写锁（writeRequests ==0），所有想获得读锁的线程都能成功获取。

通过writeLock()获取写锁，当一个线程想获得写锁的时候，首先会把写锁请求数加1（writeRequests++），然后再去判断是否能够真能获得写锁，当没有线程持有读锁（readers==0 ）,且没有线程持有写锁（writers==0）时就能获得写锁。有多少线程在请求写锁并无关系。

简单说就是：

- 读读共享
- 写写互斥
- 读写互斥
- 写读互斥

## AQS（AbstractQueuedSynchronizer）

锁分为“公平锁”和“非公平锁”，顾名思义：

- 公平锁：线程获取锁的顺序是按照线程加锁的顺序来分配的，FIFO。
- 非公平锁：是一种获取锁的抢占机制，是随机获得锁的，先来的不一定先得到锁，可能导致某些线程一直拿不到锁。

```java
    public ReentrantLock() {
        sync = new NonfairSync();
    }
	public ReentrantLock(boolean fair) {
        sync = fair ? new FairSync() : new NonfairSync();
    }

	public ReentrantReadWriteLock(boolean fair) {
        sync = fair ? new FairSync() : new NonfairSync();
        readerLock = new ReadLock(this);
        writerLock = new WriteLock(this);
    }
```

其中`FairSyncAQS`和`NonfairSync`继承`ReentrantLock.Sync`和`ReentrantReadWriteLock.Sync`，而他们都是AbstractQueuedSynchronizer（简称AQS）的子类。AQS是基于FIFO队列实现的，AQS整个类中没有任何一个abstract的抽象方法，取而代之的是，需要子类去实现的那些方法通过一个方法体抛出UnsupportedOperationException异常来让子类知道，告知如果没有实现这些方法，则直接抛出异常。

| 方法名            | 方法描述                                                     |
| ----------------- | ------------------------------------------------------------ |
| tryAcquire        | 以独占模式尝试获取锁，独占模式下调用acquire，尝试去设置state的值，如果设置成功则返回，如果设置失败则将当前线程加入到等待队列，直到其他线程唤醒 |
| tryRelease        | 尝试独占模式下释放状态                                       |
| tryAcquireShared  | 尝试在共享模式获得锁，共享模式下调用acquire，尝试去设置state的值，如果设置成功则返回，如果设置失败则将当前线程加入到等待队列，直到其他线程唤醒 |
| tryReleaseShared  | 尝试共享模式下释放状态                                       |
| isHeldExclusively | 是否是独占模式，表示是否被当前线程占用                       |

这里以ReentrantLock的公平锁来举例，看一下AQS内部是如何实现锁的获取和释放。

```java
    // ReentrantLock.FairSync
	final void lock() {
        acquire(1);
    }

	// AbstractQueuedSynchronizer
	public final void acquire(int arg) {
        // 第一步尝试获取锁，成功则返回
        // 获取锁失败后通过addWaiter添加到CLH队列的末尾
        // 通过acquireQueued判断是否轮到自己唤醒了
        if (!tryAcquire(arg) &&
            acquireQueued(addWaiter(Node.EXCLUSIVE), arg))
            selfInterrupt();
    }

    /**
     * ReentrantLock.FairSync
     *
     * Fair version of tryAcquire.  Don't grant access unless
     * recursive call or no waiters or is first.
     */
    protected final boolean tryAcquire(int acquires) {
        final Thread current = Thread.currentThread();
        int c = getState();
        if (c == 0) {
            // hasQueuedPredecessors判断是否是队列的第一个元素，如果是则尝试获取锁（CAS更新state）
            if (!hasQueuedPredecessors() &&
                compareAndSetState(0, acquires)) {
                setExclusiveOwnerThread(current);
                return true;
            }
        }
        // 判断获取到当前锁的线程是否是当前线程，可重入性体现在这里
        else if (current == getExclusiveOwnerThread()) {
            int nextc = c + acquires;
            if (nextc < 0)
                throw new Error("Maximum lock count exceeded");
            setState(nextc);
            return true;
        }
        return false;
    }
	// AbstractQueuedSynchronizer
    final boolean acquireQueued(final Node node, int arg) {
        boolean failed = true;
        try {
            boolean interrupted = false;
            for (;;) {
                final Node p = node.predecessor();
                // 如果前一个节点是head，当前节点排在第二，那么便有资格去尝试获取资源
                if (p == head && tryAcquire(arg)) {
                    setHead(node);
                    p.next = null; // help GC
                    failed = false;
                    return interrupted;
                }
                if (shouldParkAfterFailedAcquire(p, node) &&
                    parkAndCheckInterrupt())
                    interrupted = true;
            }
        } finally {
            if (failed)
                cancelAcquire(node);
        }
    }
	
	// ReentrantLock
    public void unlock() {
        sync.release(1);
    }
	// AbstractQueuedSynchronizer
    public final boolean release(int arg) {
        // 释放锁
        if (tryRelease(arg)) {
            Node h = head;
            if (h != null && h.waitStatus != 0)
                // 释放head.next
                unparkSuccessor(h);
            return true;
        }
        return false;
    }
```

> AQS只提供固定的方法给子类实现，就可以实现不同的功能，这个满足设么类设计原则，那么又使用了什么设计模式？

# 同步工具

## CountDownLatch：减法计数器

countDown() 执行一次计数器减一，await() 等待计数器停止，唤醒其他线程，示例如下：

```java
public class CountDownLatchTest {
    public static void main(String[] args) {
        //优先执行，执行完毕之后，才能执行 main
        //1、实例化计数器，10
        CountDownLatch countDownLatch = new CountDownLatch(10);
        new Thread(() -> {
            for (int i = 0; i < 10; i++) {
                System.out.println("++++++++++Thread");
                countDownLatch.countDown();
            }
        }).start();
        //2、调用 await 方法 让主线程等待countdonwn运行完毕
        try {
            countDownLatch.await();
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
        System.out.println("main--------------");
    }
}
```

## CyclicBarrier：加法计数器

await()执行一次计数器加一，执行次数完成后，再执行CyclicBarrier的Runnable，示例如下：

```java
public class TestCyclicBarrier {
    public static void main(String[] args) {
        CyclicBarrier barrier = new CyclicBarrier(20, () -> {
            System.out.println(Thread.currentThread().getName() + ":完成最后任务");
        });

        for (int i = 0; i < 20; i++) {
            new Thread(() -> {
                try {
                    System.out.println(Thread.currentThread().getName() + "到达");
                    Thread.sleep(100);
                    barrier.await();
                } catch (InterruptedException | BrokenBarrierException e) {
                    e.printStackTrace();
                }
            }).start();
        }
    }
}
```

> countDownLatch是一个计数器，线程完成一个记录一个，计数器递减，只能只用一次。
>
> CyclicBarrier的计数器更像一个阀门，需要所有线程都到达，然后继续执行，计数器递增，提供reset功能，可以多次使用。

## Semaphore：计数信号量

实际开发中主要用来做限流操作，即限制可以访问某些资源的线程数量。

- 初始化
- 获取许可
- 释放许可

```java
public class SemaphoreTest {
    public static void main(String[] args) {
        //同时只能进5个人
        Semaphore semaphore = new Semaphore(5);
        for (int i = 0; i < 15; i++) {
            new Thread(()->{
                try {
                    //获得许可
                    semaphore.acquire();
                    System.out.println(Thread.currentThread().getName()+"进店购物");
                    TimeUnit.SECONDS.sleep(5);
                    System.out.println(Thread.currentThread().getName()+"出店");
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }finally {
                    //释放许可
                    semaphore.release();
                }
            },String.valueOf(i)).start();
        }
    }
}
```

## Exchanger：数据交换

Exchanger 是 JDK 1.5 开始提供的一个用于两个工作线程之间交换数据的封装工具类，简单说就是一个线程在完成一定的事务后想与另一个线程交换数据，则第一个先拿出数据的线程会一直等待第二个线程，直到第二个线程拿着数据到来时才能彼此交换对应数据。

```java
public class ExchangerTest {
    static Exchanger<String> exchanger = new Exchanger<>();

    public static void main(String[] args) {
        Thread t1 = new Thread(() -> {
            String t = "t1";
            try {
                t = exchanger.exchange(t);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            System.out.println(Thread.currentThread().getName() + "-" + t);
        });
        Thread t2 = new Thread(() -> {
            String t = "t2";
            try {
                t = exchanger.exchange(t);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            System.out.println(Thread.currentThread().getName() + "-" + t);
        });
        t1.start();
        t2.start();
    }
}
```

# 线程池（ThreadPool）

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

详细内容请点：[线程池详解](https://fanzhongwei.com/mutlithreading/thread-pool.html)

# 并发容器

一起来回想下，java中的容器有哪几种，List、Set、Queue、Map？

大家熟知的这些集合类ArrayList、HashSet、HashMap这些容器都是非线程安全的。

比如Vector、Stack、Hashtable以及Collections.synchronized等方法生成的容器都是线程安全的，通过查看源码可以知道**这些容器都在需要同步的方法上加上了`synchronized`关键字**，在高并发的情况下容器的吞吐量就会降低，为了解决性能问题就有了**并发容器**。

## ConcurrentHashMap

对应的非并发容器：HashMap

目标：代替Hashtable、synchronizedMap，支持复合操作

原理：JDK6中采用一种更加细粒度的加锁机制Segment“分段锁”，JDK8中采用CAS无锁算法。

## CopyOnWriteArrayList

对应的非并发容器：ArrayList

目标：代替Vector、synchronizedList

原理：利用高并发往往是读多写少的特性，对读操作不加锁，对写操作，先复制一份新的集合，在新的集合上面修改，然后将新集合赋值给旧的引用，并通过volatile 保证其可见性，当然写操作的锁是必不可少的了。

## CopyOnWriteArraySet

对应的非并发容器：HashSet

目标：代替synchronizedSet

原理：基于CopyOnWriteArrayList实现，其唯一的不同是在add时调用的是CopyOnWriteArrayList的addIfAbsent方法，其遍历当前Object数组，如Object数组中已有了当前元素，则直接返回，如果没有则放入Object数组的尾部，并返回。

## ConcurrentSkipListMap

对应的非并发容器：TreeMap

目标：代替synchronizedSortedMap(TreeMap)

原理：Skip list（跳表）是一种可以代替平衡树的数据结构，默认是按照Key值升序的。

## ConcurrentSkipListSet

对应的非并发容器：TreeSet

目标：代替synchronizedSortedSet

原理：内部基于ConcurrentSkipListMap实现。

## ConcurrentLinkedQueue

不会阻塞的队列

对应的非并发容器：Queue

原理：基于链表实现的FIFO队列（LinkedList的并发版本）

## LinkedBlockingQueue

对应的非并发容器：BlockingQueue

特点：拓展了Queue，增加了可阻塞的插入和获取等操作

原理：通过ReentrantLock实现线程安全，通过Condition实现阻塞和唤醒

**实现类：**

- LinkedBlockingQueue：基于链表实现的可阻塞的FIFO队列
- ArrayBlockingQueue：基于数组实现的可阻塞的FIFO队列
- PriorityBlockingQueue：按优先级排序的队列

# 产考文献

- http://ifeve.com/java-concurrency-thread-directory/
- http://tutorials.jenkov.com/java-concurrency/index.html
- https://fanzhongwei.com/thread/h5/thread.html