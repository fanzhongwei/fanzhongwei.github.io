---
title: 多线程编程--并发包
date: 2020-05-11
tags: 
	- java
	- java多线程
	- 多线程编程
	- 线程安全
	- JUC
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

## ReentrantLock

除了使用`synchronized`关键字保证线程安全之外，还能够使用`java.util.concurrent.locks`包中所提供的Lock，先来看一个简单的例子吧。

```java
    private int instanceNum;
    private Lock lock = new ReentrantLock();
    private void addInstanceNum(String username) {
        try {
            lock.lock();
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

锁分为“公平锁”和“非公平锁”，ReentrantLock默认是非公平锁
- 公平锁：线程获取锁额顺序是按照线程枷锁的顺序来分配的，FIFO。
- 非公平锁：是一种获取锁的抢占机制，是随机获得锁的，先来的不一定先得到锁，可能导致某些线程一直拿不到锁。

```java
    public ReentrantLock() {
        sync = new NonfairSync();
    }
	public ReentrantLock(boolean fair) {
        sync = fair ? new FairSync() : new NonfairSync();
    }
```

## ReadWriteLock




# 线程池（ThreadPool）



# 并发（Concurrent）





# 产考文献

- http://ifeve.com/java-concurrency-thread-directory/
- http://tutorials.jenkov.com/java-concurrency/index.html
- https://fanzhongwei.com/thread/h5/thread.html