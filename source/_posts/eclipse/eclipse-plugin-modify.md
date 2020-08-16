---
title: Eclipse插件修改之旅
date: 2020-08-16
tags: 
	- 软件开发
	- Eclipse
	- 插件修改
categories:
	- 开发工具
---

大家有没有遇到Eclipse有些插件有问题，但是又不知道怎么修改，接下来就教大家如何修改Eclipse的插件。
![Eclispe插件开发.png](https://s1.ax1x.com/2020/08/16/dVSHUO.png)

<!-- more -->

# 背景

最近MyEclipse老是出现内存溢出，错误信息如下：

```
!ENTRY org.eclipse.core.jobs 4 2 2020-08-11 11:08:00.677
!MESSAGE An internal error occurred during: "JSP Index Manager: Processing Resource Events".
!STACK 0
java.lang.OutOfMemoryError: unable to create native thread: possibly out of memory or process/resource limits reached
	at java.base/java.lang.Thread.start0(Native Method)
	at java.base/java.lang.Thread.start(Thread.java:803)
	at org.eclipse.sapphire.java.jdt.internal.JdtJavaTypeReferenceService$1.elementChanged(JdtJavaTypeReferenceService.java:91)
```

第一反应应该是调MyEclipse内存，但是一看不对，报错是无法创建线程，然后用Java VisualVM工具监控，发现线程实时峰值最高达到9532，如下图所示：

![线程监控.png](https://s1.ax1x.com/2020/08/11/aLcbnS.png)

然后dump出线程日志，发现3000+线程都阻塞的：

![线程日志情况.png](https://s1.ax1x.com/2020/08/11/aLgY9I.png)

经查阅这些线程都是由sapphire插件创建的，插件的介绍：Create models that reference Java types in Eclipse Java projects.

找到对应的org.eclipse.sapphire.java.jdt_9.1.1.201712191343.jar反编译看看：

```java
    Thread thread = new Thread()
      {
        public void run()
        {
          if (!value.disposed() && !value.root().disposed())
          {
            JdtJavaTypeReferenceService.null.this.this$0.refresh();
          }
        }
      };
    thread.start();
```

果然都是直接创建的线程，估计插件开发者没有考虑到会发生阻塞的情况，当代码变化量比较大的时候，比如git分支切换，workspace又在干其它事儿的时候，这个地方就会创建大量线程，导致内存溢出。

# 解决方案

## 修改插件源码

于是呼就想着先把这个问题处理了，修改源码，使用线程池。

那么问题来了，怎么修改这个插件的源码呢。

首先打开 window->show view，选择 plugin-ins。

如果没有就先要安装，打开 Help -> Install New Software，

work with 选择 --All Available Sites--，在下面找到 Plugin-in Development（好像是这个，不太记得了，看到就清楚）。

下面的操作就是next，finish之类的。



打开plugin-ins后，找到 org.eclipse.sapphire.java.jdt，右键单击，选择import as -> source project，导入之后在你的 workspace

就可以看到这个project，如果没有src文件，你还得去下载源码。

源码链接：http://ftp.gnome.org/mirror/eclipse.org/sapphire/9.1.1/repository/plugins/

下载后复制到Eclipse安装目录下的.\eclipse\plugins文件夹下，重启Eclipse，

重新import as就看到src文件夹了。

![plugin.png](https://s1.ax1x.com/2020/08/11/aLRpeU.png)

然后找到`JdtJavaTypeReferenceService`类，修改对应代码，使用线程池：

```java
    threadPool.execute(new Runnable() {

        @Override
        public void run() {
            if( ! value.disposed() && ! value.root().disposed() )
            {
                refresh();
            }
        }
    });
```

## 打包插件

接下只剩下打包，然后替换测试了，项目右键-》Plug-in Tools-》Open Manifest，然后开始打包，如下图所示：

![plugin-deploy.png](https://s1.ax1x.com/2020/08/11/aLRhtJ.png)

最后替换到eclipse插件目录测试，当然记得备份。

到这里eclipse插件修改圆满结束。