---
title: 多线程编程--基础知识
date: 2020-05-24
tags: 
	- java
	- java多线程
	- 多线程编程
categories:
	- java多线程
---

**线程**（Thread）是操作系统能够进行运算调度的最小单位，java线程中创建的、引用的对象在jvm内存中是如何存放的，线程间是如何进行通信的呢，线程发生异常了jvm又是如何处理的呢，接下来让我们从线程的基础知识开始一步一步地了解。

![多线程编程](https://s2.ax1x.com/2019/04/13/AL3oVS.png)

<!-- more -->

# 线程基础知识

## 什么是线程

**线程**（Thread）是操作系统能够进行运算调度的最小单位。它被包含在进程之中，是进程中的实际运作单位。一条线程指的是进程中一个单一顺序的控制流，一个进程中可以并发多个线程，每条线程并行执行不同的任务。

## 如何创建线程

- 继承Thread类

```java
    /**
     * 继承Thread类
     */
    static class ThreadTest extends Thread{
        @Override
        public void run(){
            super.run();
            System.out.println("Hello World! This is my first Thread.");
        }
    }

    @Test
    public void extendsThreadTest() throws InterruptedException {
        ThreadTest threadTest = new ThreadTest();
        threadTest.start();
        System.out.println("运行结束。");
        Thread.sleep(10);
    }
```

- 实现Runnable接口

```java
    /**
     * 实现Runnable接口
     */
    static class RunnableTest implements Runnable{
        @Override
        public void run() {
            System.out.println("Hello World! This is my first Thread.");
        }
    }
        @Test
    public void implementsRunnableTest() throws InterruptedException {
        RunnableTest runnableTest = new RunnableTest();
        Thread thread = new Thread(runnableTest);
        thread.start();

        Thread.sleep(1000);
        System.out.println("运行结束。");
    }
```

## 线程的状态

Java中的线程一共有六种状态：

- NEW（初始化状态）
- RUNNABLE（可运行 / 运行状态）
- BLOCKED（阻塞状态）
- WAITING（无时限等待）
- TIMED_WAITING（有时限等待）
- TERMINATED（终止状态）

线程可以在这六种状态之间相互转换，如图所示：

![线程状态切换.jpg](https://s1.ax1x.com/2020/05/23/YvfvDg.jpg)

# 内存模型

## java内存模型

- 每一个运行在Java虚拟机里的线程都拥有自己的线程栈，存放当前线程运行的信息。
- 所有原始类型的本地变量都存放在线程栈上，因此对其它线程不可见。
- 所有引用类型的本地变量都存放在堆中，线程栈保存该对象的引用，因此其他线程只要有该对象的引用都可以访问。
- Java程序中无论由哪个对象创建的对象，不管是原始类型对象，还是引用类型对象，都是存放在堆里面。

接下来让我们先看看一段具体代码，这些变量都存放在JVM的什么位置。

```java
public class MemoryModel {

    private static class MemorySharedObject {
        private static MemorySharedObject sharedObject = new MemorySharedObject();
        public Integer object2 = new Integer(222);
        public Integer object4 = new Integer(444);

        public long member1 = 12345L;
        public long member2 = 67890L;
    }

    private static List<Object> list = Collections.synchronizedList(new ArrayList<>());

    @Test
    public void test() throws InterruptedException {
        new Thread(this::methodOne).start();
        new Thread(this::methodOne).start();

        Thread.sleep(100000);
    }

    private void methodOne() {
        int localVariable1 = 999;
        MemorySharedObject localVariable2 = MemorySharedObject.sharedObject;

        list.add(localVariable2);
        methodTwo();
    }

    private void methodTwo() {
        Integer localVariable1 = new Integer(4321);
        list.add(localVariable1);
    }
}
```

当test用例执行的时候，各个变量在jvm内存中存放位置如下图所示：

![YxN3LT.png](https://s1.ax1x.com/2020/05/23/YxN3LT.png)

上图中每个线程执行`methodOne()`都会在它们对应的线程栈上创建`localVariable1`和`localVariable2`的私有拷贝。`localVariable1`为基础类型对象只存在于线程栈上，`localVariable2`为堆内存中Object3的引用。methodTwo方法中的localVariable1都会各自在堆上创建一个对象`object1`和`object5`，线程栈中存放这两个对象的引用。

执行test用例的时候，我们执行如下两个步骤：

- jmap -dump:format=b,file=./heap_dump.txt 12792
- dump出jvm内存后，使用mat进行分析，可以找到本例中对象的情况

分析结果如下如所示：

![mat内存分析.png](https://s1.ax1x.com/2020/05/24/tS30OS.png)

## 硬件内存模型

![YxN0Qx.png](https://s1.ax1x.com/2020/05/23/YxN0Qx.png)

## java内存模型与硬件内存模型的关系

![YxNxXV.png](https://s1.ax1x.com/2020/05/23/YxNxXV.png)

# 同步异步

**同步和异步关注的是：消息通信机制(synchronous communication/ asynchronous communication)。**

## 同步（Synchronous）

**同步方法**调用一旦开始，调用者必须等到方法调用返回后，才能继续后续的行为，如下图所示：

![同步.png](https://img2018.cnblogs.com/blog/1680783/201905/1680783-20190521124754180-1985908967.png)

> - 打电话
> - B/S模式

## 异步（Asynchronous）

**异步方法**调用更像一个消息传递，一旦开始，方法调用就会立即返回，调用者就可以继续后续的操作。而，异步方法通常会在另外一个线程中，“真实”地执行着。整个过程，不会阻碍调用者的工作，如下图所示：

![同步.png](https://img2018.cnblogs.com/blog/1680783/201905/1680783-20190521125411515-1327485285.png)

> - 发短信
> - ajax
> - 消息队列

## 阻塞和非阻塞

**阻塞和非阻塞**：强调的是程序在等待调用结果（消息，返回值）时的状态。

阻塞调用是指调用结果返回之前，当前线程会被挂起，调用线程只有在得到结果之后才会返回。

非阻塞调用指在不能立刻得到结果之前，该调用不会阻塞当前线程。 

# 线程间通信

## 共享对象

线程间发送信号的一个简单方式是在共享对象的变量里设置信号值，如下面代码所示：

```java
    private static class MySignal {
        private boolean hasDataToProcess = false;
        public synchronized boolean hasDataToProcess() {
            return this.hasDataToProcess;
        }
        public synchronized void setHasDataToProcess(boolean process){
            this.hasDataToProcess = process;
        }
    }
```

线程A在一个同步块里设置boolean型成员变量hasDataToProcess为true，线程B也在同步块里读取hasDataToProcess这个成员变量。

```java
    @Test
    public void test_share_signal() {
        MySignal signal = new MySignal();
        new Thread(() -> {
            while(!signal.hasDataToProcess()) {
                System.out.println("线程A未接收到信号，sleep 1000ms");
                sleep(1000);
            }
            System.out.println("线程A接收到信号了，开始处理：" + data.remove(0));
        }).start();

        sleep(10000);

        new Thread(() -> {
            System.out.println("线程B设置信号");
            data.add("线程B设置的数据");
            signal.setHasDataToProcess(true);
        }).start();
    }
```

注意：**线程A和B必须获得指向一个MySignal共享实例的引用，否则线程A将收不到信号。**

## wait(),notify()和notifyAll()

通过共享对象，循环检测信号是否被设置，如果没有被设置则进入等待，等待的间隔时间设置过短则对cpu消耗过大，等待的间隔时间设置过长则消息接收不及时。

Java有一个内建的等待机制来允许线程在等待信号的时候变为非运行状态。java.lang.Object 类定义了三个方法，wait()、notify()和notifyAll()来实现这个等待机制。

一个线程一旦调用了任意对象的wait()方法，就会变为非运行状态，直到另一个线程调用了同一个对象的notify()方法。为了调用wait()或者notify()，线程必须先获得那个对象的锁，也就是说，线程必须在同步块里调用wait()或者notify()，否则将抛出`java.lang.IllegalMonitorStateException`异常。

```
	@Test
    public void test_wait_notify() {
        Object monitor = new Object();
        List<String> data = new ArrayList<>();
        Thread thread = new Thread(() -> {
            try {
                synchronized (monitor) {
                    System.out.println("子线程开始等待notify信号");
                    monitor.wait();
                }
                System.out.println("子线程接收到notify信号了，开始处理：" + data.remove(0));
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        });
        thread.start();

        sleep(3000);
        data.add("主线程调用notify方法");
        synchronized (monitor) {
            monitor.notify();
        }
    }
```

一旦线程调用了wait()方法，它就释放了所持有的监视器对象上的锁。这将允许其他线程也可以调用wait()或者notify()。一旦一个线程被唤醒，不能立刻就退出wait()的方法调用，直到调用notify()的线程退出了它自己的同步块。换句话说：**被唤醒的线程必须重新获得监视器对象的锁，才可以退出wait()的方法调用，因为wait方法调用运行在同步块里面。**如果多个线程被notifyAll()唤醒，那么在同一时刻将只有一个线程可以退出wait()方法，因为每个线程在退出wait()前必须获得监视器对象的锁。

# 异常处理

## Thread默认的异常处理

线程都不允许抛出未捕获的checked exception（比如sleep时的`InterruptedException`）**，也就是说各个线程需要自己把自己的checked exception处理掉**。我们可以查看一下Thread类的run()方法声明，方法声明上没有对抛出异常进行约束。

```java
    //Thread类中
    @Override
    public void run() {
        if (target != null) {
            target.run();//实际上直接调用Runnable实例的run方法
        }
    }
    
    //Runnable接口中
    public abstract void run();
```

**线程是独立执行的代码片断，线程的问题应该由线程自己来解决，而不要委托到外部。**

## 未捕获的异常去哪儿了

一个异常被抛出后，如果没有被捕获处理，则会一直向上抛。<font color="red">**异常一旦被Thread.run() 抛出后，就不能在程序中对异常进行捕获，最终只能由JVM捕获。**</font>

```java
    @Test
    public void test_thread_exception() {
        new Thread(() -> {int a = 1/0;}).start();
    }

// 执行结果
Exception in thread "Thread-0" java.lang.ArithmeticException: / by zero
	at com.teddy.thread.basic.ThreadExceptionTest.lambda$thread_exception$0(ThreadExceptionTest.java:9)
	at java.lang.Thread.run(Thread.java:748)
    
    @Test
    public void test_catch_thread_exception() {
        try {
            new Thread(() -> {int a = 1/0;}).start();
        } catch (Exception e) {
            System.out.println("捕获到线程抛出的异常！");
            e.printStackTrace();
        }
    }
// 执行结果
Exception in thread "Thread-0" java.lang.ArithmeticException: / by zero
	at com.teddy.thread.basic.ThreadExceptionTest.lambda$test_catch_thread_exception$1(ThreadExceptionTest.java:18)
	at java.lang.Thread.run(Thread.java:748)
```

## JVM如何处理线程中抛出的异常

查看Thread类的源码，我们可以看到有个dispatchUncaughtException方法，此方法就是用来处理线程中抛出的异常的。JVM会调用dispatchUncaughtException方法来寻找异常处理器(UncaughtExceptionHandler)，处理异常。

```java
    // 向handler分派未捕获的异常。该方法仅由JVM调用。
    private void dispatchUncaughtException(Throwable e) {
        getUncaughtExceptionHandler().uncaughtException(this, e);
    }

    // 获取用来处理未捕获异常的handler，如果没有设置则返回当前线程所属的ThreadGroup
    public UncaughtExceptionHandler getUncaughtExceptionHandler() {
        return uncaughtExceptionHandler != null ?
            uncaughtExceptionHandler : group;
    }
```

UncaughtExceptionHandler必须显示的设置，否则默认为null。若为null，则使用线程默认的handler，即该线程所属的ThreadGroup。ThreadGroup自身就是一个handler，查看ThreadGroup的源码就可以发现，ThreadGroup实现了Thread.UncaughtExceptionHandler接口，并实现了默认的处理方法。默认的未捕获异常处理器处理时，会调用 System.err 进行输出，也就是直接打印到控制台了。

```java
    public void uncaughtException(Thread t, Throwable e) {
        if (parent != null) { // 父级优先处理
            parent.uncaughtException(t, e);
        } else {
            Thread.UncaughtExceptionHandler ueh = Thread.getDefaultUncaughtExceptionHandler();
            if (ueh != null) {
                ueh.uncaughtException(t, e);
            } else if (!(e instanceof ThreadDeath)) { 
                // 没有配置handler时，默认直接打印到控制台
                System.err.print("Exception in thread \""
                                 + t.getName() + "\" ");
                e.printStackTrace(System.err);
            }
        }
    }
```



# 产考文献

- http://ifeve.com/java-concurrency-thread-directory/
- http://tutorials.jenkov.com/java-concurrency/index.html
- https://fanzhongwei.com/thread/h5/thread.html
- 《深入Java虚拟机：JVM高级特性与最佳实践（第2版）》

