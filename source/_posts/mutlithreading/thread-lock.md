---
title: 多线程编程与锁优化
date: 2019-04-15
tags: 
	- java
	- java多线程
	- 多线程编程
	- lock
categories:
	- java多线程
---



多线程是在同一个程序内部并行执行，因此会对相同的内存空间进行并发读写操作。如果一个线程在读一个内存时，另一个线程正向该内存进行写操作，那进行读操作的那个线程将获得什么结果呢？是写操作之前旧的值？还是写操作成功之后的新值？或是一半新一半旧的值？或者，如果是两个线程同时写同一个内存，在操作完成后将会是什么结果呢？是第一个线程写入的值？还是第二个线程写入的值？还是两个线程写入的一个混合值？从下面的图我们可以窥知一二。

![Java memory model](https://s2.ax1x.com/2019/04/14/AO9UHK.png)

<!-- more -->

# 多线程基础知识

## 竞态条件与临界区

在同一程序中运行多个线程本身不会导致问题，问题在于多个线程访问了相同的资源。在一或多个线程向这些资源做了写操作时才有可能发生，只要资源没有发生变化,多个线程读取相同的资源就是安全的。

```java
public class Counter {
	protected long count = 0;
	public void add(long value){
		this.count = this.count + value;  
	}
}
```

JVM并不是将这段代码：`this.count = this.count + value;`，视为单条指令来执行的，而是按照下面的顺序：
> 从内存获取 this.count 的值放到寄存器
>
> 将寄存器中的值增加value
>
> 将寄存器中的值写回内存

当线程A和线程B同时执行add方法时，他们的实际执行顺序可能如下：

> this.count = 0;
>
> A:读取 this.count 到一个寄存器 (0)
>
> B:读取 this.count 到一个寄存器 (0)
>
> B:将寄存器的值加2
>
> B:回写寄存器值(2)到内存. this.count 现在等于 2
>
> A:将寄存器的值加3
>
> A:回写寄存器值(3)到内存. this.count 现在等于 3

当两个线程竞争同一资源时，如果对资源的访问顺序敏感，就称存在竞态条件。导致竞态条件发生的代码区称作临界区。上例中add()方法就是一个临界区,它会产生竞态条件。在临界区中使用适当的同步就可以避免竞态条件。


## 共享资源

允许被多个线程同时执行的代码称作线程安全的代码，线程安全的代码不包含竞态条件，当多个线程同时更新共享资源时会引发竞态条件。

### 局部变量

局部变量存储在线程自己的栈中。也就是说，局部变量永远也不会被多个线程共享。所以，基础类型的局部变量是线程安全的。下面是基础类型的局部变量的一个例子：

```java
    /**
     * 方法内的变量是线程安全的
     * @param username
     */
    private void addI(String username){
        try {
            int num;
            if("a".equals(username)){
                num = 100;
                System.out.println("a set over!");
                Thread.sleep(2000);
            }else{
                num = 200;
                System.out.println("b set over!");
            }
            System.out.println(username + " num = " + num);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    @Test
    public void threadSetPrivateNumTest() throws InterruptedException {
        Thread threadA = new Thread(()->addI("a"));
        Thread threadB = new Thread(()->addI("b"));
        threadA.start();
        threadB.start();
        Thread.sleep(3000);
    }
```

### 局部的对象引用

对象的局部引用和基础类型的局部变量不太一样。尽管引用本身没有被共享，但引用所指的对象并没有存储在线程的栈内。所有的对象都存在共享堆中。如果在某个方法中创建的对象不会逃逸出（译者注：即该对象不会被其它方法获得，也不会被非局部变量引用到）该方法，那么它就是线程安全的。

```java
public class ThreadSafeTest {
	private int instanceNum;
    private void addInstanceNum(String username){
        try {
            if("b".equals(username)){
                instanceNum = 200;
                System.out.println("b set over!");
            }else{
                instanceNum = 100;
                System.out.println("a set over!");
                Thread.sleep(2000);
            }
            System.out.println(username + " num = " + instanceNum);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }
	@Test
    public void localObjectTest() throws InterruptedException {
        addInstanceNum("a");
        addInstanceNum("b");
    }
}
```

上面的示例中，localObject没有传递到其它线程中，那么它就是线程安全的，如果传到其它线程了呢？

```java
	@Test
    public void localObjectTest() throws InterruptedException {
        ThreadSafeTest test = new ThreadSafeTest();
        Thread threadA = new Thread(()->addInstanceNum("a"));
        Thread threadB = new Thread(()->addInstanceNum("b"));
        threadA.start();
        threadB.start();
        Thread.sleep(3000);
    }
```
上面的示例中，localObject虽然是局部变量，但是在someMethod方法中将其引用传入到线程A和线程B中，他们的结果可能就不是预期的，那么localObject就不是线程安全的。

### 对象成员

对象成员存储在堆上，如果两个线程同时更新同一个对象的同一个成员，那这个代码就不是线程安全的，详情参考[竞态条件与临界区](#竞态条件与临界区)。

## 线程控制逃逸规则

线程控制逃逸规则可以帮助你判断代码中对某些资源的访问是否是线程安全的。

```java
如果一个资源的创建，使用，销毁都在同一个线程内完成，
且永远不会脱离该线程的控制，则该资源的使用就是线程安全的。
```

# 多线程编程

## 并发编程三要素

当多个线程要共享一个实例对象的值得时候，那么在考虑安全的多线程并发编程时就要保证下面3个要素：

- 原子性（Synchronized, Lock）

即一个操作或者多个操作 要么全部执行并且执行的过程不会被任何因素打断，要么就都不执行。

- 有序性(Volatile, Synchronized, Lock)

可见性是指当多个线程访问同一个变量时，一个线程修改了这个变量的值，其他线程能够立即看得到修改的值。

- 可见性(Volatile, Synchronized, Lock)

即程序执行的顺序按照代码的先后顺序执行。

## 线程安全的实现方法

### 互斥同步--悲观锁

互斥同步（Mutual Exclusion & Synchronization）是常见的一种并发正确性保障手段。同步是指在多个线程并发访问共享数据时，保证共享数据在同一个时刻只被一个（或者是一些，使用信号量的时候）线程使用。而互斥是实现同步的一种手段，临界区（Critical Section）、互斥量（Mutex）和信号量（Semaphore）都是主要的互斥实现方式。因此，在这4个字里面，互斥是因，同步是果；互斥是方法，同步是目的。

这种方式实现的锁，总是假设最坏的情况，每次去拿数据的时候都认为别人会修改，所以每次在拿数据的时候都会上锁，这样别人想拿这个数据就会阻塞直到它拿到锁（**共享资源每次只给一个线程使用（独占锁），其它线程阻塞，用完后再把资源转让给其它线程**）。所以这也是悲观锁的思想的一种实现方式。

#### synchronized

在Java中，最基本的互斥同步手段就是synchronized关键字，synchronized关键字经过编译之后，会在同步块的前后分别形成monitorenter和monitorexit这两个字节码指令，这两个字节码都需要一个reference类型的参数来指明要锁定和解锁的对象。如果Java程序中的synchronized明确指定了对象参数，那就是这个对象的reference；如果没有明确指定，那就根据synchronized修饰的是实例方法还是类方法，去取对应的对象实例或Class对象来作为锁对象。

```java
void methodB(){
    synchronized (this){
        methodA();
    }
}
这段代码编译之后的字节码如下：
 0 aload_0 // 入栈this
 1 dup	// 复制栈顶元素
 2 astore_1	// 将栈顶元素存储到局部变量表Slot 1中
 3 monitorenter // 以栈顶元素（即this）作为锁，开始同步
 4 aload_0 // 入栈this，用于调用methodA
 5 invokevirtual #19 <com/teddy/thread/basic/ThreadSafeTest$SyncMethodLockTest.methodA> // 调用methodA
 8 aload_1 // 入栈this，monitorexit的reference
 9 monitorexit // 退出同步
10 goto 18 (+8) // 方法正常结束，跳转到18返回
13 astore_2 // 异常路径
14 aload_1 // 入栈this，用于调用methodA
15 monitorexit // 退出同步
16 aload_2 // 异常对象入栈
17 athrow // 抛出异常给调用者
18 return // 方法结束
```

从上面了解到，synchronized修饰符在不同方法上以及同步构造器中传入的参数不同，监视的对象是不同的，大致分为以下几种情况：

- 实例方法

```java
synchronized void methodB(){
    System.out.println("threadName = " + Thread.currentThread().getName() + " enter sync methodB.");
    try {
        Thread.sleep(2000);
    } catch (InterruptedException e) {
        e.printStackTrace();
    }
    System.out.println("threadName = " + Thread.currentThread().getName() + " leave sync methodB.");
}
```

Java实例方法同步是同步在拥有该方法的对象上。这样，每个实例其方法同步都同步在不同的对象上，即该方法所属的实例对象。

- 静态方法

```java
synchronized static void methodA(){
    System.out.println("threadName = " + Thread.currentThread().getName() + " enter sync static methodA.");
    try {
        Thread.sleep(2000);
    } catch (InterruptedException e) {
        e.printStackTrace();
    }
    System.out.println("threadName = " + Thread.currentThread().getName() + " leave sync static methodA.");
}
```

静态方法的同步是指同步在该方法所在的类对象上。因为在Java虚拟机中一个类只能对应一个类对象(即只能被一个ClassLoader加载)，所以同时只允许一个线程执行同一个类中的静态同步方法。

- 实例方法中的同步块

```java
void methodA() {
    System.out.println("methodA time = " + System.currentTimeMillis());
    synchronized (this){
        System.out.println("methodA begin time = " + System.currentTimeMillis());
        try {
            Thread.sleep(2000);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
        System.out.println("methodA end time = " + System.currentTimeMillis());
    }
}
```

在同步构造器中用括号括起来的对象叫做监视器对象。同时只有一个线程能够在同步于同一个监视器对象的Java方法内执行。

- 静态方法中的同步块

```java
private static class InStaticMethodSync{
    public static void methodA(){
        synchronized(InStaticMethodSync.class){
            System.out.println("methodA begin time = " + System.currentTimeMillis());
            try {
                Thread.sleep(2000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }
        System.out.println("methodA begin time = " + System.currentTimeMillis());
    }
    public static void methodB(){
        synchronized(InStaticMethodSync.class){
            System.out.println("methodB begin time = " + System.currentTimeMillis());
            try {
                Thread.sleep(2000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }
        System.out.println("methodB begin time = " + System.currentTimeMillis());
    }
}
```

这个地方同步构造器中是InStaticMethodSync.class，那么这里监视的就是class对象，因此InStaticMethodSync.class的其它被synchronized修饰的静态方法与该同步块同时只有一个线程能够执行。

>摘抄自《深入理解Java虚拟机：JVM高级特性与最佳实践（第二版）》
>
>根据虚拟机规范的要求，在执行monitorenter指令时，首先要尝试获取对象的锁。如果这个对象没被锁定，或者当前线程已经拥有了那个对象的锁，把锁的计数器加1，相应的，在执行monitorexit指令时会将锁计数器减1，当计数器为0时，锁就被释放。如果获取对象锁失败，那当前线程就要阻塞等待，直到对象锁被另外一个线程释放为止。
>在虚拟机规范对monitorenter和monitorexit的行为描述中，有两点是需要特别注意的。首先，synchronized同步块对同一条线程来说是可重入的，不会出现自己把自己锁死的问题。其次，同步块在已进入的线程执行完之前，会阻塞后面其他线程的进入。Java的线程是映射到操作系统的原生线程之上的，如果要阻塞或唤醒一个线程，都需要操作系统来帮忙完成，这就需要从用户态转换到核心态中，因此状态转换需要耗费很多的处理器时间。对于代码简单的同步块（如被synchronized修饰的getter()或setter()方法），状态转换消耗的时间有可能比用户代码执行的时间还要长。所以synchronized是Java语言中一个重量级（Heavyweight）的操作，有经验的程序员都会在确实必要的情况下才使用这种操作。而虚拟机本身也会进行一些优化，譬如在通知操作系统阻塞线程之前加入一段自旋等待过程，避免频繁地切入到核心态之中。

#### Lock

synchronized同步块一样，是一种线程同步机制，但比Java中的synchronized同步块更复杂。 自Java 5开始，java.util.concurrent.locks包中包含了一些锁的实现，因此我们不用去实现自己的锁了。但是我们仍然需要去了解怎样使用这些锁，且了解这些实现背后的理论也是很有用处的。

##### 锁的使用

以之前的代码为例，使用Lock代替synchronized达到了同样的目的 ：

```java
    private Lock lock = new ReentrantLock();

    /** 实例变量非线程安全的 */
    private int instanceNum;
    private void addInstanceNum(String username){
        try {
            lock.lock();
            if("b".equals(username)){
                instanceNum = 200;
                System.out.println("b set over!");
            }else{
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
        Thread threadA = new Thread(()->addInstanceNum("a"));
        Thread threadB = new Thread(()->addInstanceNum("b"));
        threadA.start();
        threadB.start();
        Thread.sleep(3000);
    }
```

lock()方法会对Lock实例对象进行加锁，因此所有对该对象调用lock()方法的线程都会被阻塞，直到该Lock对象的unlock()方法被调用。 

##### 锁的简单实现

```java
public class SimpleLock{
	private boolean isLocked = false;
	public synchronized void lock()
		throws InterruptedException{
		while(isLocked){
			wait();
		}
		isLocked = true;
	}
	public synchronized void unlock(){
		isLocked = false;
		notify();
	}
}
```

注意其中的while(isLocked)循环，它又被叫做“自旋锁”。自旋锁以及wait()和notify()方法在[线程通信](http://ifeve.com/thread-signaling/)这篇文章中有更加详细的介绍。当isLocked为true时，调用lock()的线程在wait()调用上阻塞等待。为防止该线程没有收到notify()调用也从wait()中返回（也称作[虚假唤醒](http://ifeve.com/thread-signaling/#spurious_wakeups)），这个线程会重新去检查isLocked条件以决定当前是否可以安全地继续执行还是需要重新保持等待，而不是认为线程被唤醒了就可以安全地继续执行了。如果isLocked为false，当前线程会退出while(isLocked)循环，并将isLocked设回true，让其它正在调用lock()方法的线程能够在Lock实例上加锁。

当线程完成了[临界区](http://ifeve.com/race-conditions-and-critical-sections/)（位于lock()和unlock()之间）中的代码，就会调用unlock()。执行unlock()会重新将isLocked设置为false，并且通知（唤醒）其中一个（若有的话）在lock()方法中调用了wait()函数而处于等待状态的线程。

java中的锁ReentrantLock不是基于synchronized而是基于原子类实现的，其核心代码如下：

```java
final void lock() {
    if (compareAndSetState(0, 1))
        setExclusiveOwnerThread(Thread.currentThread());
    else
        acquire(1);
}
// 第一步compareAndSetState失败时，表示已经有线程获取到锁了，那么调用acquire请求锁
public final void acquire(int arg) {
    // 先尝试一下，能否请求到锁，不能请求到锁的话，开始排队请求锁(排队的请求者存放在链表中)
    if (!tryAcquire(arg) &&
        acquireQueued(addWaiter(Node.EXCLUSIVE), arg))
        selfInterrupt();
}
final boolean acquireQueued(final Node node, int arg) {
    boolean failed = true;
    try {
        boolean interrupted = false;
      	// 这里有个死循环，知道请求到锁，其实也就是CAS
        for (;;) {
            final Node p = node.predecessor();
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
```



#### 可重入性

Java中的synchronized同步块是可重入的，使用以下代码来进行分析：

```java
static class ReentrantSyncMethodTest{
    synchronized void methodA(){
        System.out.println("methodA");
        methodB();
    }
    synchronized void methodB(){
        System.out.println("methodB");
    }
}
@Test
/**
 * 可重入锁：自己可以再次获取自己的内部锁
 *
 * 如果不可重入的话
 * 线程进入methodA获取了该对象的锁，然后执行methodB还是需要获取该对象的锁，
 * 但是methodA还没有执行完不会将锁释放，就会造成死锁。
 */
public void reentrantSyncMethodTest(){
    ReentrantSyncMethodTest reentrantSyncMethodTest = new ReentrantSyncMethodTest();
    Thread thread = new Thread(()-> reentrantSyncMethodTest.methodA());
    thread.start();
}
```

 到这里想一想，我们之前的`SimpleLock`是否是可重入锁，很明显它不是，获取锁的条件是：只有当isLocked为false时lock操作才被允许，而没有考虑是哪个线程锁住了它。 



为了让SimpleLock具有可重入性，我们只需要对其进行简单修改即可：

```java
public class SimpleReentrantLock{
    boolean isLocked = false;
    Thread  lockedBy = null;
    int lockedCount = 0;

    public synchronized void lock()
            throws InterruptedException{
        Thread callingThread =
                Thread.currentThread();
        while(isLocked && lockedBy != callingThread){
            wait();
        }
        isLocked = true;
        lockedCount++;
        lockedBy = callingThread;
    }

    public synchronized void unlock(){
        if(Thread.currentThread() ==
                this.lockedBy){
            lockedCount--;
            if(lockedCount == 0){
                isLocked = false;
                notify();
            }
        }
    }
}
```

注意到现在的while循环（自旋锁）也考虑到了已锁住该Lock实例的线程。如果当前的锁对象没有被加锁(isLocked = false)，或者当前调用线程已经对该Lock实例加了锁，那么while循环就不会被执行，调用lock()的线程就可以退出该方法。

除此之外，我们需要记录同一个线程重复对一个锁对象加锁的次数。否则，一次unblock()调用就会解除整个锁，即使当前锁已经被加锁过多次。在unlock()调用没有达到对应lock()调用的次数之前，我们不希望锁被解除。

现在这个Lock类就是可重入的了。

java中的ReentrantLock实现方式与SimpleReentrantLock实现方式大同小异：

```java
final boolean nonfairTryAcquire(int acquires) {
    final Thread current = Thread.currentThread();
    int c = getState();
    // 当前状态为1的话，就表示已经有线程获取到锁了
    if (c == 0) {
        if (compareAndSetState(0, acquires)) {
            setExclusiveOwnerThread(current);
            return true;
        }
    }
    // 如果持有锁的线程是当前线程的话，直接返回true，表示已经请求到锁了，可重入行也就体现在这里
    else if (current == getExclusiveOwnerThread()) {
        int nextc = c + acquires;
        if (nextc < 0) // overflow
            throw new Error("Maximum lock count exceeded");
        setState(nextc);
        return true;
    }
    return false;
}
```

#### 公平性

Java的synchronized块并不保证尝试进入它们的线程的顺序。因此，如果多个线程不断竞争访问相同的synchronized同步块，就存在一种风险，其中一个或多个线程永远也得不到访问权 —— 也就是说访问权总是分配给了其它线程。这种情况被称作线程饥饿。为了避免这种问题，锁需要实现公平性。本文所展现的锁在内部是用synchronized同步块实现的，因此它们也不保证公平性。 

`ReentrantLock、ReentrantReadWriteLock`可以通过构造函数指定是否为公平锁，其核心代码如下：

```java
// 默认实现
final boolean nonfairTryAcquire(int acquires) {
	···
    // 当有一个线程将锁释放了，这里的状态就为0了
    if (c == 0) {
        // 这里所有的等待线程都会进行这个CAS操作，谁能抢到就看运气了，所以是不公平的
        if (compareAndSetState(0, acquires)) {
            setExclusiveOwnerThread(current);
            return true;
        }
    }  
    ···
}
// 公平锁的实现
final boolean tryAcquire(int acquires) {
	···
    // 当有一个线程将锁释放了，这里的状态就为0了
    if (c == 0) {
        // 这里进行CAS之前会判断一下，是否是排在链表最前端的线程，如果是则进行CAS操作，所以是公平的
        if (!hasQueuedPredecessors() && compareAndSetState(0, acquires)) {
            setExclusiveOwnerThread(current);
            return true;
        }
    }  
    ···
}
public final boolean hasQueuedPredecessors() {
    Node t = tail; 
    Node h = head;
    Node s;
  	// 1、h == t 表示只有一个等待线程，直接获取锁即可
    // 2、h.next == null 表示只有一个等待线程，直接获取锁即可
    // 3、s.thread != Thread.currentThread() 排在链表最前端的不是当前线程，那么继续进入等待，知道当前线程排在最前端
    return h != t &&
        ((s = h.next) == null || s.thread != Thread.currentThread());
}
```

#### 读写锁

读锁的获取条件：没有线程拥有写锁（writers==0），且没有线程在请求写锁（writeRequests ==0） 

写锁的获取条件：当一个线程想获得写锁的时候，首先会把写锁请求数加1（writeRequests++），然后再去判断是否能够真能获得写锁，当没有线程持有读锁（readers==0 ）,且没有线程持有写锁（writers==0）时就能获得写锁。有多少线程在请求写锁并无关系。 

### 非阻塞同步--乐观锁

>摘抄自《深入理解Java虚拟机：JVM高级特性与最佳实践（第二版）》
>
>互斥同步最主要的问题就是进行线程阻塞和唤醒所带来的性能问题，因此这种同步也称为阻塞同步（Blocking Synchronization）。随着硬件指令集的发展，我们有了另外一个选择：基于冲突检测的乐观并发策略，通俗地说，就是先进行操作，如果没有其他线程争用共享数据，那操作就成功了；如果共享数据有争用，产生了冲突，那就再采取其他的补偿措施（最常见的补偿措施就是不断地重试，直到成功为止），这种乐观的并发策略的许多实现都不需要把线程挂起，因此这种同步操作称为非阻塞同步（Non-Blocking Synchronization）。
>
>为什么笔者说使用乐观并发策略需要“硬件指令集的发展”才能进行呢？因为我们需要操作和冲突检测这两个步骤具备原子性，靠什么来保证呢？如果这里再使用互斥同步来保证就失去意义了，所以我们只能靠硬件来完成这件事情，硬件保证一个从语义上看起来需要多次操作的行为只通过一条处理器指令就能完成，这类指令常用的有：
>
> - 测试并设置（Test-and-Set）。
> - 获取并增加（Fetch-and-Increment）。
> - 交换（Swap）。
> - 比较并交换（Compare-and-Swap，下文称CAS）。
> - 加载链接/条件存储（Load-Linked/Store-Conditional，下文称LL/SC）。
>
>其中，前面的3条是20世纪就已经存在于大多数指令集之中的处理器指令，后面的两条是现代处理器新增的，而且这两条指令的目的和功能是类似的。在IA64、x86指令集中有cmpxchg指令完成CAS功能，在sparc-TSO也有casa指令实现，而在ARM和PowerPC架构下，则需要使用一对ldrex/strex指令来完成LL/SC的功能。
>CAS指令需要有3个操作数，分别是内存位置（在Java中可以简单理解为变量的内存地址，用V表示）、旧的预期值（用A表示）和新值（用B表示）。CAS指令执行时，当且仅当V符合旧预期值A时，处理器用新值B更新V的值，否则它就不执行更新，但是无论是否更新了V的值，都会返回V的旧值，上述的处理过程是一个原子操作。

java中AtomicInteger的自增实现如下：

```java
public final int incrementAndGet() {
    for (;;) {
        int current = get();
        int next = current + 1;
        if (compareAndSet(current, next))
            return next;
    }
}
```

JDK1.8起，Unsafe提供了compareAndSwapInt方法底层由C实现，直接实现了CAS操作：

```java
public final boolean compareAndSet(int expect, int update) {
    return unsafe.compareAndSwapInt(this, valueOffset, expect, update);
}
```

CAS操作有个逻辑漏洞：如果一个变量V初次读取的时候是A值，并且在准备赋值的时候检查到它仍然为A值，那我们就能说它的值没有被其他线程改变过了吗？如果在这段期间它的值曾经被改成了B，后来又被改回为A，那CAS操作就会误认为它从来没有被改变过。这个漏洞称为CAS操作的“ABA”问题。J.U.C包为了解决这个问题，提供了一个带有标记的原子引用类“AtomicStampedReference”，它可以通过控制变量值的版本来保证CAS的正确性。不过目前来说这个类比较“鸡肋”，大部分情况下ABA问题不会影响程序并发的正确性，如果需要解决ABA问题，改用传统的互斥同步可能会比原子类更高效。

### 无同步方案

保证线程安全，并不是一定要进行同步的，两者没有因果关系。如果方法不涉及共享数据，那么它也不需要进行同步了。

- 可重入代码
  - 不依赖存储在堆上的数据和共用的资源
  - 在入参相同的情况，执行结果都是相同的
- 线程本地存储
  - 共享数据的代码放到同一个线程执行
  - ThreadLocal

## 锁优化

#### 自旋锁与自适应自旋

互斥同步对性能最大的影响是阻塞的实现，挂起线程和恢复线程的操作都需要转入内核态中完成，这些操作给系统的并发性能带来了很大的压力。同时，虚拟机的开发团队也注意到在许多应用上，共享数据的锁定状态只会持续很短的一段时间，为了这段时间去挂起和恢复线程并不值得。如果物理机器有一个以上的处理器，能让两个或以上的线程同时并行执行，我们就可以让后面请求锁的那个线程“稍等一下”，但不放弃处理器的执行时间，看看持有锁的线程是否很快就会释放锁。为了让线程等待，我们只需让线程执行一个忙循环（自旋），这项技术就是所谓的自旋锁。
自旋等待本身虽然避免了线程切换的开销，但它是要占用处理器时间的，因此，**如果锁被占用的时间很短，自旋等待的效果就会非常好**，反之，**如果锁被占用的时间很长，那么自旋的线程只会白白消耗处理器资源**，而不会做任何有用的工作，反而会带来性能上的浪费。因此，**自旋等待的时间必须要有一定的限度**，如果自旋超过了限定的次数仍然没有成功获得锁，就应当使用传统的方式去挂起线程了。自旋次数的默认值是10次，用户可以使用参数-XX:PreBlockSpin来更改。
在JDK 1.6中引入了自适应的自旋锁。自适应意味着自旋的时间不再固定了，而是由前一次在同一个锁上的自旋时间及锁的拥有者的状态来决定。如果在同一个锁对象上，自旋等待刚刚成功获得过锁，并且持有锁的线程正在运行中，那么虚拟机就会认为这次自旋也很有可能再次成功，进而它将允许自旋等待持续相对更长的时间，比如100个循环。另外，如果对于某个锁，自旋很少成功获得过，那在以后要获取这个锁时将可能省略掉自旋过程，以避免浪费处理器资源。有了自适应自旋，随着程序运行和性能监控信息的不断完善，虚拟机对程序锁的状况预测就会越来越准确，虚拟机就会变得越来越“聪明”了。

#### 锁消除

锁消除是指虚拟机即时编译器在运行时，对一些代码上要求同步，但是被检测到不可能存在共享数据竞争的锁进行消除。锁消除的主要判定依据来源于逃逸分析的数据支持，如果判断在一段代码中，堆上的所有数据都不会逃逸出去从而被其他线程访问到，那就可以把它们当做栈上数据对待，认为它们是线程私有的，同步加锁自然就无须进行。

#### 锁粗化

原则上，我们在编写代码的时候，总是推荐将同步块的作用范围限制得尽量小——只在共享数据的实际作用域中才进行同步，这样是为了使得需要同步的操作数量尽可能变小，如果存在锁竞争，那等待锁的线程也能尽快拿到锁。
大部分情况下，上面的原则都是正确的，但是如果一系列的连续操作都对同一个对象反复加锁和解锁，甚至加锁操作是出现在循环体中的，那即使没有线程竞争，频繁地进行互斥同步操作也会导致不必要的性能损耗。

#### 轻量级锁

“轻量级”是相对于使用操作系统互斥量来实现的传统锁而言的，因此传统的锁机制就称为“重量级”锁。首先需要强调一点的是，轻量级锁并不是用来代替重量级锁的，它的本意是在没有多线程竞争的前提下，减少传统的重量级锁使用操作系统互斥量产生的性能消耗。

使用轻量级锁时，不需要申请互斥量，仅仅*将Mark Word中的部分字节CAS更新指向线程栈中的Lock Record，如果更新成功，则轻量级锁获取成功*，记录锁状态为轻量级锁；**否则，说明已经有线程获得了轻量级锁，目前发生了锁竞争（不适合继续使用轻量级锁），接下来膨胀为重量级锁**。

> Mark Word是对象头的一部分；每个线程都拥有自己的线程栈（虚拟机栈），记录线程和函数调用的基本信息。

#### 偏向锁

“偏向”的意思是，*偏向锁假定将来只有第一个申请锁的线程会使用锁*（不会有任何线程再来申请锁），因此，*只需要在Mark Word中CAS记录owner（本质上也是更新，但初始值为空），如果记录成功，则偏向锁获取成功*，记录锁状态为偏向锁，*以后当前线程等于owner就可以零成本的直接获得锁；否则，说明有其他线程竞争，膨胀为轻量级锁*。

偏向锁无法使用自旋锁优化，因为一旦有其他线程申请锁，就破坏了偏向锁的假定。

# 参考文献

- [并发编程网--Java并发性和多线程介绍 ](http://ifeve.com/java-concurrency-thread-directory/)
- 《深入理解Java虚拟机：JVM高级特性与最佳实践（第二版）》
