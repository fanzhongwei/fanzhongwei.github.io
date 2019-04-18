---
title: 单例模式
data: 2019-03-22
tags: 
	- java
	- 设计模式
categories:
	- java设计模式
---

在GoF的23种设计模式中，单例模式是比较简单的一种。然而，有时候越是简单的东西越容易出现问题。下面就单例设计模式详细的探讨一下。
所谓单例模式，简单来说，就是在整个应用中保证只有一个类的实例存在。就像是Java Web中的application，也就是提供了一个全局变量，用处相当广泛，比如保存全局数据，实现全局性的操作等。

![d602986de5753f457ee357a85bd45209.png](https://i.loli.net/2019/04/13/5cb18b0bbbd52.png)

<!-- more -->

# 最简单实现(饿汉)
```java
public class Singleton{
    private static final Singleton singleton = new Singleton();
    
    public static Singleton getInstance(){
        return singleton;
    }
    
    private Singleton(){
    
    }
}
```
外部使用者如果需要使用SingletonClass的实例，只能通过getInstance()方法，并且它的构造方法是private的，这样就保证了只能有一个对象存在。


# 性能优化--lazy loaded(懒汉)
上面的代码虽然简单，但是有一个问题----无论这个类是否被使用，都会创建一个instance对象。如果这个创建很耗时，比如说链接10000次数据库（夸张一点啦....），并且这个类还不一定会被使用，那么这个创建过程就是无用的，怎么办呢？
```java
public class SingletonClass { 
  private static SingletonClass instance = null; 
    
  public static SingletonClass getInstance() { 
    if(instance == null) { 
      instance = new SingletonClass(); 
    } 
    return instance; 
  }

  private SingletonClass() { 
     
  }
}
```
要使用 SingletonClass，调用getInstance（）方法，第一次的时候发现instance时null,然后就创建一个对象，返回出去；第二次再使用的时候，因为这个instance是static的，共享一个内存地址的，所以instance的值已经不是null了，因此不会再创建对象，直接将其返回。这个过程就称为lazyloaded,也就是迟加载-----直到使用的时候才经行加载。

# 线程安全
上面的代码很清楚，也很简单。然而就像那句名言：“80%的错误是由20%的代码优化引起的”。单线程下，这段代码没什么问题，可是如果是多线程呢，麻烦就来了，我们来分析一下：


- 线程A希望使用SingletonClass，调用getInstance()方法。因为是第一次调用，A就发现instance是null的，于是它开始创建实例，就在这个时候，CPU发生时间片切换，
- 线程B开始执行，它要使用SingletonClass，调用getInstance()方法，同样检测到instance是null——注意，这是在A检测完之后切换的，也就是说A并没有来得及创建对象——因此B开始创建。
- B创建完成后，切换到A继续执行，因为它已经检测完了，所以A不会再检测一遍，它会直接创建对象。这样，线程A和B各自拥有一个SingletonClass的对象——单例失败！
解决的办法也很简单，那就是加锁：
```java
public class SingletonClass{
    private static SingletonClass instance = null;
    public synchronized static SingletonClass getInstance(){
        if(instance == null){
            instance = new SingletonClass();
        }
        return instance;
    }
    private SingletonClass(){
    
    } 
}
```
只要getInstance（）加上同步锁，，一个线程必须等待另外一个线程创建完后才能使用这个方法，这就保证了单例的唯一性。
# 双重检查锁定(double--checked--locking)
上面这段代码毫无疑问存在性能的问题----synchronized修饰的同步块可是要比一般的代码慢上几倍的！如果存在很多次的getInstance()调用，那性能问题就不得不考虑了？！！！


究竟是整个方法都必须加锁，还是紧紧其中某一句加锁就足够了？我们为什么要加锁呢？分析一下lazy loaded的那种情形的原因，原因就是检测null的操作和创建对象的操作分离了，导致出现只有加同步锁才能单利的唯一性。
如果这俩个操作能够原子的进行，那么单利就已经保证了。于是，我们开始修改代码：
```java
public class SingletonClass{
    private static SingletonClass instance = null;
    public static SingletonClass getInstance(){
        synchronized(SingletonClass.class){
            if(instance == null){
            instance = new SingletonClass();
            }
        }
        return instance;
    }
    private SingletonClass(){
    
    } 
}
```
首先去掉 getInstance() 的同步操作，然后把同步锁加载到if语句上。但是，这样的修改起不到任何作用：因为每次调用getInstance()的时候必然要经行同步，性能的问题还是存在。如果............我们事先判断一下是不是为null在去同步呢？
```java
public class SingletonClass{
    private static SingletonClass instance = null;
    public static SingletonClass getInstance(){
        if(instance == null){
            synchronized(SingletonClass.class){
                if(instance == null){
                    instance = new SingletonClass();
                }
            }
        }    
        return instance;
    }
    private SingletonClass(){
    
    } 
}
```
首先判断instance是不是为null，如果为null在去进行同步，如果不为null，则直接返回instance对象。这就是double---checked----locking设计实现单例模式。

# 并发编程--有序性

并发编程中，我们通常会遇到以下三个问题：原子性问题，可见性问题，有序性问题。我们上面的单例实现是否都解决了。

- [X] 原子性：即一个操作或者多个操作 要么全部执行并且执行的过程不会被任何因素打断，要么就都不执行。

- [X] 可见性：可见性是指当多个线程访问同一个变量时，一个线程修改了这个变量的值，其他线程能够立即看得到修改的值。

- [ ] 有序性：即程序执行的顺序按照代码的先后顺序执行。

编译原理里面有一个很重要的内容是编译器优化。所谓编译器优化是指，在不改变原来语义的情况下，通过调整语句顺序，来让程序运行的更快。这称为指令重排序(Instruction Reorder)。

初始化Singleton和将对象地址赋给instance字段的顺序是不确定的。在某个线程创建单例对象时，在构造方法被调用之前，就为该对象分配了内存空间并将分配的内存地址赋值给instance字段了，然而该对象可能还没有初始化。若紧接着另外一个线程来调用getInstance，此时instance不是null，但取到的对象还未真正初始化，程序就会出错。

在JDK1.5之前，volatile是个关键字，但是并没有明确的规定其用途。在JDK1.5之后，volatile关键字有了明确的语义---是禁止指令重排序优化，被volatile修饰的写变量不能和之前的读写代码调整，读变量不能和之后的读写代码调整！因此，只要我们简单的把instance加上volatile关键字就可以了。
```java
public class SingletonClass{
    private static volatile SingletonClass instance = null;
    public static SingletonClass getInstance(){
        if(instance == null){
            synchronized(SingletonClass.class){
                if(instance == null){
                    instance = new SingletonClass();
                }
            }
        }    
        return instance;
    }
    private SingletonClass(){
    
    } 
}
```
# 静态内部类
代码如下：
```java
public class SingletonClass { 
  private static class SingletonClassInstance { 
    private static final SingletonClass instance = new SingletonClass(); 
  } 

  public static SingletonClass getInstance() { 
    return SingletonClassInstance.instance; 
  } 

  private SingletonClass() { 

  } 
}
```
SingletonClass没有static的属性，因此并不会被初始化。直到调用getInstance()的时候，会首先加载SingletonClassInstance类，这个类有一个static的SingletonClass实例，因此需要调用SingletonClass的构造方法，然后getInstance()将把这个内部类的instance返回给使用者。由于这个instance是static的，因此并不会构造多次。
 
由于SingletonClassInstance是私有静态内部类，所以不会被其他类知道，同样，static语义也要求不会有多个实例存在。并且，JSL规范定义，类的构造必须是原子性的，非并发的，因此不需要加同步块。同样，由于这个构造是并发的，所以getInstance()也并不需要加同步。
# 序列化问题（枚举、readResolve）

```java
public class SingletonClass { 
  private static class SingletonClassInstance { 
    private static final SingletonClass instance = new SingletonClass(); 
  } 

  public static SingletonClass getInstance() { 
    return SingletonClassInstance.instance; 
  } 

  private SingletonClass() { 

  } 
  
  private Object readResolve(){
      return SingletonClassInstance.instance;
  }
}
```
JVM从内存中反序列化地"组装"一个新对象时,就会自动调用这个 readResolve方法来返回我们指定好的对象了, 单例规则也就得到了保证。

# 枚举
```java
public enum Singleton{  
    instance;  
    public void whateverMethod(){}      
} 
```
使用枚举除了线程安全和防止反射调用构造器之外，还提供了自动序列化机制，防止反序列化的时候创建新的对象。因此，《Effective Java》作者推荐使用的方法。

# 反射问题（第二次实例化的时候，抛出异常）
```java
public class SingletonClass { 
  private static boolean isInstanced = false;
    
  private static class SingletonClassInstance { 
    private static final SingletonClass instance = new SingletonClass(); 
  } 

  public static SingletonClass getInstance() { 
    return SingletonClassInstance.instance; 
  } 

  private SingletonClass() { 
        if(!instanced){
            instanced = true;
        }else{
            throw new Exception("duplicate instance create error!" + SingletonClass.class.getName());  
        }
  } 
}
```





