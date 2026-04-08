---
title: 性能优化利器-javaagent
date: 2024-09-13
tags:
  - 性能优化
  - Java
  - JavaAgent
categories:
  - 性能优化
---

# 性能优化利器-javaagent

你在做性能优化时有没有遇到过，知道某些接口慢但是**不知道具体慢在哪里**。当然你可能第一时间会想到使用阿里的arthas去trace一下就能看到调用栈上各个方法耗时了；但是在生产环境一般是单次访问不慢，高并发时才慢，再用arthas去trace就监控生产环境就不太现实了。

> 如果你第一时间想到的是给各个方法调用加上耗时日志打印，然后根据日志再去分析哪里慢，那么你更应该把这篇文章看完！

## javaagent

接下来给大家介绍的工具叫[javaagent](https://github.com/dingjs/javaagent)，javaagent 是一个简单优雅的 java agent ,利用 java 自带的 instrument 特性+ javassist 字节码编辑技术，实现了无侵入的方法级性能监控。相比于NewRelic或者开源的[pinpoint](https://github.com/naver/pinpoint),以及阿里的[arthas](https://github.com/alibaba/arthas),本工具主打的是简单，我们只记录每个方法的执行次数和时间，并输出到json格式的日志文件中，然后可以使用配套的agent-analyer进行分析。

集成方式详见：[https://github.com/dingjs/javaagent](https://github.com/dingjs/javaagent)

监控出来的统计结果：

| 类名 | 方法名 | 总时间 | 总次数 | 平均数 |
| --- | --- | --- | --- | --- |
| com.xxx.ClassA | 	methodA | 778015748 | 2052812 | 379 |
| com.xxx.ClassA | 	methodB | 757438182 | 2052678 | 369 |
| com.xxx.ClassA | 	methodC | 162202981 | 2052678 | 79 |


> 从这个统计结果来看，方法运行了205万次，平均时间为379ms，看起来不慢。
> 但是，性能测试的时候发现有的请求响应时间很长，JMeter聚合报告中`90%百分位`为2356ms，也就是说有10%的请求响应时间是大于等于2356ms。

从统计结果来看平均响应时间都还很不错，但是对于性能优化来说不能直接的找出慢的方法，那么有没有办法能像JMeter聚合报告那样计算出方法执行耗时的百分比统计结果呢，我们继续往下看。

## T-Digest在线计算

[T-Digest](https://github.com/tdunning/t-digest)是由Ted Dunning提出，旨在以极低的内存开销计算数据流的大致百分位数。不同于传统的精确计算方法要求大量内存来存储所有数据，tdigest通过聪明的数据结构和算法优化，能够在压缩数据到极小内存空间的同时，提供高质量的百分位数估计。

通过对比最终决定采用MergingDigest算法进行方法执行的统计，这里使用简单的demo进行验证：
```java
public void testMethodPctCounter() {
        int compression = 150;
        int factor = 5;

        final int M = 100;
        final List<MergingDigest> mds = new ArrayList<MergingDigest>(M);
        final long[] counts = new long[M];
        for (int i = 0; i < M; ++i) {
            mds.add(new MergingDigest(compression, (factor + 1) * compression, compression));
            counts[i] = 0;
        }

        // Fill all digests with random values (0~100).
        final Random random = new Random();

        ThreadPoolExecutor executorService = new ThreadPoolExecutor(
                100,
                100,
                0,
                TimeUnit.MINUTES,
                new ArrayBlockingQueue<Runnable>(1000),
                new ThreadPoolExecutor.CallerRunsPolicy());
        for (int i = 0; i < 5000000; ++i) {
            executorService.execute((new Runnable() {
                @Override
                public void run() {
                    for (int j = 0; j < M; ++j) {
                        MergingDigest md = mds.get(j);
                        synchronized (md) {
                            int data = random.nextInt(101);
                            long start = System.currentTimeMillis();
                            md.add(data);
                            counts[j] = counts[j] + (System.currentTimeMillis() - start);
                        }
                    }
                }
            }));
        }
        while (true) {
            if (executorService.getActiveCount() != 0) {
                try {
                    Thread.sleep(100);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
            } else {
                break;
            }
        }
        executorService.shutdown();

        // Output
        double[] qArr = new double[]{0.1, 0.2, 0.25, 0.5, 0.75, 0.90, 0.95, 0.99};
        System.out.printf("%10s\t", "MIN");
        for (int i = 0 ; i < qArr.length; ++i) {
            System.out.printf("%4sth pct\t", (int)(qArr[i] * 100));
        }
        System.out.printf("%10s\t", "MAX");
        System.out.printf("%10s\t", "耗时");
        System.out.println();
        for (int i = 0 ; i < 11; ++i) {
            System.out.print("==========\t");
        }
        System.out.println();


        for (int i = 0; i < mds.size(); ++i) {
            MergingDigest md = mds.get(i);
            System.out.printf("%10.0f\t", md.getMin());
            long start = System.currentTimeMillis();
            for (double q : qArr) {
                System.out.printf("%10.0f\t", md.quantile(q));
            }
            counts[i] = counts[i] + (System.currentTimeMillis() - start);
            System.out.printf("%10.0f\t", md.getMax());
            System.out.printf("%10d\t", counts[i]);
            System.out.println();
        }

    }
```

100个线程并发测试，每个线程往100个不同的Digest中添加5000000个随机数据[0, 100]，并计算耗时，jvm内存限制为：-Xms50m -Xmx50m。部分统计结果如下：
```
       MIN	  10th pct	  20th pct	  25th pct	  50th pct	  75th pct	  90th pct	  95th pct	  99th pct	       MAX	        耗时
==========	==========	==========	==========	==========	==========	==========	==========	==========	==========	==========
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       942
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       869
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       939
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       895
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       942
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       845
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       887
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       898
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       911
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       815
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       762
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       893
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       933
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       866
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       863
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       920
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       830
         0	        10	        20	        25	        50	        75	        90	        95	        99	       100	       870
         0	        10	        20	        25	        50	        75	        90	        95	       100	       100	       913  
```

**测试结论**：从统计值来看，统计结果基本符合预期，并且耗时基本在800ms~1000ms之间，未发生内存溢出，初步评估可以加入到javaagent方法耗时统计中并且对性能影响在可控范围内。

因此fork出[https://github.com/dingjs/javaagent](https://github.com/dingjs/javaagent)仓库添加方法执行的百分比统计功能，配置方式在agent.properties配置文件中添加如下配置：

```
# 是否统计方法执行时间百分比，同JMeter性能测试百分比计算方式，如果开启默认会统计最大值、最小值
agent.log.stat.execute.time=false
# 方法执行时间统计百分比（agent.log.stat.execute.time=true时有效），多选范围[0, 1]，例如：0.5,0.9,0.95,0.99
agent.log.stat.execute.time.pct=0.5,0.9,0.95,0.99
```

最终监控出来的统计结果：

| 类名 | 方法名 | 总时间 | 总次数 | 平均数 | 最小值 | 最大值 | 中位数 | 90th pct | 95th pct | 99th pct |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| com.xxx.ClassA | 	methodA | 778015748 | 2052812 | 379 | 10 | 4399 | 1029 | 2356 | 3476 | 4399 |
| com.xxx.ClassA | 	methodB | 757438182 | 2052678 | 369 | 10 | 4399 | 1029 | 2356 | 3476 | 4399 |
| com.xxx.ClassA | 	methodC | 162202981 | 2052678 | 79 | 10 | 1499 | 125 | 468 | 1276 | 1399 |

最终该修改顺利地合并回[https://github.com/dingjs/javaagent](https://github.com/dingjs/javaagent)仓库，合并请求：[https://github.com/dingjs/javaagent/pull/12](https://github.com/dingjs/javaagent/pull/12)

至此可以尽情地使用javaagent工具帮助我们快乐地进行性能优化了\^_\^

## 参考文档

- [https://github.com/dingjs/javaagent](https://github.com/dingjs/javaagent)
- [https://jmeter.apache.org/usermanual/component_reference.html#Aggregate_Report](https://jmeter.apache.org/usermanual/component_reference.html#Aggregate_Report)
- [https://github.com/tdunning/t-digest](https://github.com/tdunning/t-digest)
