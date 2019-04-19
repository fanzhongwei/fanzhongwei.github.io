---
title: 支持生产阻塞的线程池
date: 2019-04-19
tags: 
	- java
	- java多线程
	- ThreadPool
categories:
	- java多线程
---


在各种并发编程模型中，生产者-消费者模式大概是最常用的了。在实际工作中，对于生产消费的速度，通常需要做一下权衡。通常来说，生产任务的速度要大于消费的速度。一个细节问题是，队列长度，以及如何匹配生产和消费的速度。

一个典型的生产者-消费者模型如下：

![image](http://ifeve.com/wp-content/uploads/2013/04/producer-consumer.png)

<!--more-->



在并发环境下利用J.U.C提供的Queue实现可以很方便地保证生产和消费过程中的线程安全。这里需要注意的是，Queue必须设置初始容量，防止生产者生产过快导致队列长度暴涨，最终触发OutOfMemory。

对于一般的生产快于消费的情况。当队列已满时，我们并不希望有任何任务被忽略或得不到执行，此时生产者可以等待片刻再提交任务，更好的做法是，把生产者阻塞在提交任务的方法上，待队列未满时继续提交任务，这样就没有浪费的空转时间了。阻塞这一点也很容易，BlockingQueue就是为此打造的，ArrayBlockingQueue和LinkedBlockingQueue在构造时都可以提供容量做限制，其中LinkedBlockingQueue是在实际操作队列时在每次拿到锁以后判断容量。

更进一步，当队列为空时，消费者拿不到任务，可以等一会儿再拿，更好的做法是，用BlockingQueue的take方法，阻塞等待，当有任务时便可以立即获得执行，建议调用take的带超时参数的重载方法，超时后线程退出。这样当生产者事实上已经停止生产时，不至于让消费者无限等待。

于是一个高效的支持阻塞的生产消费模型就实现了。



等一下，既然J.U.C已经帮我们实现了线程池，为什么还要采用这一套东西？直接用ExecutorService不是更方便？

我们来看一下ThreadPoolExecutor的基本结构：

![image](http://ifeve.com/wp-content/uploads/2013/04/threadpoolexecutor.png)

可以看到，在ThreadPoolExecutor中，BlockingQueue和Consumer部分已经帮我们实现好了，并且直接采用线程池的实现还有很多优势，例如线程数的动态调整等。

但问题在于，即便你在构造ThreadPoolExecutor时手动指定了一个BlockingQueue作为队列实现，事实上当队列满时，execute方法并不会阻塞，原因在于ThreadPoolExecutor调用的是BlockingQueue非阻塞的offer方法：


```java
public void execute(Runnable command) {
    if (command == null)
        throw new NullPointerException();
    if (poolSize >= corePoolSize || !addIfUnderCorePoolSize(command)) {
        if (runState == RUNNING && workQueue.offer(command)) {
            if (runState != RUNNING || poolSize == 0)
                ensureQueuedTaskHandled(command);
        }
        else if (!addIfUnderMaximumPoolSize(command))
            reject(command); // is shutdown or saturated
    }
}
```

这时候就需要做一些事情来达成一个结果：当生产者提交任务，而队列已满时，能够让生产者阻塞住，等待任务被消费。

关键在于，在并发环境下，队列满不能由生产者去判断，不能调用ThreadPoolExecutor.getQueue().size()来判断队列是否满。

线程池的实现中，当队列满时会调用构造时传入的RejectedExecutionHandler去拒绝任务的处理。默认的实现是AbortPolicy，直接抛出一个RejectedExecutionException。

几种拒绝策略在这里就不赘述了，这里和我们的需求比较接近的是CallerRunsPolicy，这种策略会在队列满时，让提交任务的线程去执行任务，相当于让生产者临时去干了消费者干的活儿，这样生产者虽然没有被阻塞，但提交任务也会被暂停。



```java
public static class CallerRunsPolicy implements RejectedExecutionHandler {

  /**
   * Creates an <tt>AbortPolicy</tt>.
   */

  public CallerRunsPolicy() { }



  /**

   * Executes task r in the caller's thread, unless the executor

   * has been shut down, in which case the task is discarded.

   * @param r the runnable task requested to be executed

   * @param e the executor attempting to execute this task

   */

  public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {

      if (!e.isShutdown()) {

          r.run();

      }

  }

}
```

但这种策略也有隐患，当生产者较少时，生产者消费任务的时间里，消费者可能已经把任务都消费完了，队列处于空状态，当生产者执行完任务后才能再继续生产任务，这个过程中可能导致消费者线程的饥饿。

参考类似的思路，最简单的做法，我们可以直接定义一个RejectedExecutionHandler，当队列满时改为调用BlockingQueue.put来实现生产者的阻塞：



```java
public class RejectedExecutionHandler() implements RejectedExecutionHandler {

  @Override
  public void rejectedExecution(Runnable r, ThreadPoolExecutor executor) {
      if (!executor.isShutdown()) {
          try {
              executor.getQueue().put(r);
          } catch (InterruptedException e) {

              // should not be interrupted
          }
      }
  }
};
```

这样，我们就无需再关心Queue和Consumer的逻辑，只要把精力集中在生产者和消费者线程的实现逻辑上，只管往线程池提交任务就行了。

相比最初的设计，这种方式的代码量能减少不少，而且能避免并发环境的很多问题。当然，你也可以采用另外的手段，例如在提交时采用信号量做入口限制等，但是如果仅仅是要让生产者阻塞，那就显得复杂了。