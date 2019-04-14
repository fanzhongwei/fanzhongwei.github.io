---
title: 线程安全与锁优化
tags: 
	- java
	- java多线程
	- 线程安全
	- lock
categories:
	- java多线程
---



多线程是在同一个程序内部并行执行，因此会对相同的内存空间进行并发读写操作。如果一个线程在读一个内存时，另一个线程正向该内存进行写操作，那进行读操作的那个线程将获得什么结果呢？是写操作之前旧的值？还是写操作成功之后的新值？或是一半新一半旧的值？或者，如果是两个线程同时写同一个内存，在操作完成后将会是什么结果呢？是第一个线程写入的值？还是第二个线程写入的值？还是两个线程写入的一个混合值？因此如没有合适的预防措施，任何结果都是可能的。而且这种行为的发生甚至不能预测，所以结果也是不确定性的。

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

当多个线程要共享一个实例对象的值得时候，那么在考虑安全的多线程并发编程时就要保证下面3个要素：

- 原子性（Synchronized, Lock）

即一个操作或者多个操作 要么全部执行并且执行的过程不会被任何因素打断，要么就都不执行。

- 有序性(Volatile, Synchronized, Lock)

可见性是指当多个线程访问同一个变量时，一个线程修改了这个变量的值，其他线程能够立即看得到修改的值。

- 可见性(Volatile, Synchronized, Lock)

即程序执行的顺序按照代码的先后顺序执行。

## 乐观锁和悲观锁

### 悲观锁

总是假设最坏的情况，每次去拿数据的时候都认为别人会修改，所以每次在拿数据的时候都会上锁，这样别人想拿这个数据就会阻塞直到它拿到锁。传统的关系型数据库里边就用到了很多这种锁机制，比如行锁，表锁等，读锁，写锁等，都是在做操作之前先上锁。

Java在JDK1.5之前都是靠 synchronized关键字保证同步的，这种通过使用一致的锁定协议来协调对共享状态的访问，可以确保无论哪个线程持有共享变量的锁，都采用独占的方式来访问这些变量。这就是一种独占锁，独占锁其实就是一种悲观锁，所以可以说 synchronized、Lock都是悲观锁。

#### synchronized
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
#### lock



##### ReentrantLock

##### ReentrantReadWriteLock

#### 悲观锁机制存在的问题

- 在多线程竞争下，加锁、释放锁会导致比较多的上下文切换和调度延时，引起性能问题。

- 一个线程持有锁会导致其它所有需要此锁的线程挂起。

- 如果一个优先级高的线程等待一个优先级低的线程释放锁会导致优先级倒置，引起性能风险。


### 乐观锁

顾名思义，就是很乐观，每次去拿数据的时候都认为别人不会修改，所以不会上锁，**但是在更新的时候会判断一下在此期间别人有没有去更新这个数据**，可以使用版本号等机制。**乐观锁适用于多读的应用类型**，这样可以提高吞吐量，像数据库提供的类似于write_condition机制，其实都是提供的乐观锁。在Java中java.util.concurrent.atomic包下面的原子类就是使用了**乐观锁的一种实现方式CAS**。

#### CAS(Compare-and-Swap)



# 参考文献

- [并发编程网--竞态条件与临界区](http://ifeve.com/race-conditions-and-critical-sections/)
- [并发编程网--线程安全与共享资源](http://ifeve.com/thread-safety/)
