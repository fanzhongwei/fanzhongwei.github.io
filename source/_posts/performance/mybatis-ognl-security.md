---
title: 性能优化-巧解MyBatis高并发下OGNL安全检查导致的全局锁瓶颈
date: 2025-12-30
tags:
  - 性能优化
  - MyBatis
  - OGNL
categories:
  - 性能优化
---

# 性能优化-巧解MyBatis高并发下OGNL安全检查导致的全局锁瓶颈


> 摘要：线上接口频繁超时，HSF线程池爆满。经排查，发现大量线程并非阻塞在数据库，而是卡在System.getProperty方法上。其根本原因是MyBatis使用的OGNL表达式引擎在每次解析动态SQL时，都会同步查询ognl.security.manager系统属性。由于Properties使用synchronized全局锁，高并发下引发严重性能瓶颈。最终通过为JVM添加-Dognl.security.manager=forceDisableOnInit参数，在初始化时即禁用安全检查，从而彻底避免了锁竞争，系统性能得到显著恢复。

## 背景

线上环境频繁报接口响应超时，很多节点同时报`[HSF-Provider] HSF thread pool is full.`，于是我们dump线程信息进行分析，发现居然大部分线程都卡在mybatis查询数据库了，我们难道遇到mybatis的性能问题了吗？


## 问题排查过程

### 线程堆栈分析


分析dump出来的线程堆栈信息，发现有752个线程都`BLOCKED`在`java.lang.System.getProperty`方法，该方法是获取JVM或操作系统中的系统属性值，具体堆栈信息如下：

```
# 752个等待获取锁的线程
"HSFBizProcessor-DEFAULT-6-thread-4702" #27229 daemon prio=10 os_prio=0 tid=0x00007f032c110800 nid=0x6a50 waiting for monitor entry [0x00007efeeaae8000]
   java.lang.Thread.State: BLOCKED (on object monitor)
	at java.util.Hashtable.get(Hashtable.java:363)
	- waiting to lock <0x00000004401b0198> (a java.util.Properties)
	at java.util.Properties.getProperty(Properties.java:969)
	at java.lang.System.getProperty(System.java:741)
	at org.apache.ibatis.ognl.OgnlRuntime.invokeMethodInsideSandbox(OgnlRuntime.java:1244)
	at org.apache.ibatis.ognl.OgnlRuntime.invokeMethod(OgnlRuntime.java:1230)
	at org.apache.ibatis.ognl.OgnlRuntime.getMethodValue(OgnlRuntime.java:2146)
	....
	
# 获取到锁的线程
"task-46" #834 prio=5 os_prio=0 tid=0x00007f02a4075000 nid=0x336 waiting for monitor entry [0x00007eff47135000]
   java.lang.Thread.State: BLOCKED (on object monitor)
	at java.util.Hashtable.get(Hashtable.java:363)
	- locked <0x00000004401b0198> (a java.util.Properties)
	at java.util.Properties.getProperty(Properties.java:969)
	at java.lang.System.getProperty(System.java:741)
	at org.apache.ibatis.ognl.OgnlRuntime.invokeMethodInsideSandbox(OgnlRuntime.java:1244)
	at org.apache.ibatis.ognl.OgnlRuntime.invokeMethod(OgnlRuntime.java:1230)
	at org.apache.ibatis.ognl.OgnlRuntime.getMethodValue(OgnlRuntime.java:2146)
	...
```

### 源码分析

从上面的堆栈信息可以看到全部都阻塞在`java.util.Hashtable.get`方法，Properties是继承Hashtable的，而众所周知Hashtable是线程安全的，我们来一起看看JDK中这两个类涉及的部分源码：

```java
public class Properties extends Hashtable<Object,Object> {

    public String getProperty(String key) {
        Object oval = super.get(key);
        String sval = (oval instanceof String) ? (String)oval : null;
        return ((sval == null) && (defaults != null)) ? defaults.getProperty(key) : sval;
    }

}

public class Hashtable<K,V>
    extends Dictionary<K,V>
    implements Map<K,V>, Cloneable, java.io.Serializable {

    public synchronized V get(Object key) {
        Entry<?,?> tab[] = table;
        int hash = key.hashCode();
        int index = (hash & 0x7FFFFFFF) % tab.length;
        for (Entry<?,?> e = tab[index] ; e != null ; e = e.next) {
            if ((e.hash == hash) && e.key.equals(key)) {
                return (V)e.value;
            }
        }
        return null;
    }

}
```

`synchronized`是悲观锁，在高并发情况下确实会有性能问题，那么为什么会有这么大的并发量同时获取系统属性呢，我们一起来看mybatis中`OgnlRuntime.invokeMethodInsideSandbox`方法中1244行在干什么呢：

```java
    private static Object invokeMethodInsideSandbox(Object target, Method method, Object[] argsArray)
            throws InvocationTargetException, IllegalAccessException {

        if (_disableOgnlSecurityManagerOnInit) {
            return method.invoke(target, argsArray);  // Feature was disabled at OGNL initialization.
        }

        try {
            // 这里就是1244行，所有线程都阻塞到这里了
            if (System.getProperty("ognl.security.manager") == null) {
                return method.invoke(target, argsArray);
            }
        } catch (SecurityException ignored) {
            // already enabled or user has applied a policy that doesn't allow read property so we have to honor user's sandbox
        }
        ...
    }
```

`ognl.security.manager`属性是为了增强OGNL表达式执行的安全性而引入的。通过启用它，可以防止恶意的OGNL表达式执行危险操作。

项目使用的是MyBatis-Plus进行动态SQL拼装，大量数据库查询都要解析OGNL表达式，每一次OGNL表达式解析都要获取一次`ognl.security.manager`属性，所以出现了大量线程阻塞在`java.util.Hashtable.get`这个方法。



> 完整源码请查看：[https://github.com/orphan-oss/ognl/blob/OGNL_3_3_0/src/main/java/ognl/OgnlRuntime.java#L1236](https://github.com/orphan-oss/ognl/blob/OGNL_3_3_0/src/main/java/ognl/OgnlRuntime.java#L1236)
>
> 我们项目mybatis的版本是3.5.9，对应的ognl版本是3.3.0，从`/mybatis-3.5.9.jar!/META-INF/maven/ognl/ognl/pom.xml`中可以看到对应的版本，mybatis是将ognl的class直接构建到了mybatis的jar包中了。

## 解决方案

上面我们通过源码分析到是由于大量的线程都在同时执行`System.getProperty("ognl.security.manager")`获取属性，而`java.util.Hashtable.get`这个方法是同步的，我们可以从减少`System.getProperty("ognl.security.manager")`的调用量的思路入手。

我们继续来看`OgnlRuntime.invokeMethodInsideSandbox`方法，当`_disableOgnlSecurityManagerOnInit`属性为true时直接反射调用方法返回结果。`_disableOgnlSecurityManagerOnInit`初始化逻辑如下：
```java
    /**
     * Control usage of the OGNL Security Manager using the JVM option:
     *   -Dognl.security.manager=true  (or any non-null value other than 'disable')
     *
     * Omit '-Dognl.security.manager=' or nullify the property to disable the feature.
     *
     * To forcibly disable the feature (only possible at OGNL Library initialization, use the option:
     *   -Dognl.security.manager=forceDisableOnInit
     *
     * Users that have their own Security Manager implementations and no intention to use the OGNL SecurityManager
     *   sandbox may choose to use the 'forceDisableOnInit' flag option for performance reasons (avoiding overhead
     *   involving the system property security checks - when that feature will not be used).
     */
    static final String OGNL_SECURITY_MANAGER = "ognl.security.manager";
    static final String OGNL_SM_FORCE_DISABLE_ON_INIT = "forceDisableOnInit";
    
    /**
     * Hold environment flag state associated with OGNL_SECURITY_MANAGER.  See
     * {@link OgnlRuntime#OGNL_SECURITY_MANAGER} for more details.
     *   Default: false (if not set).
     */
    private static final boolean _disableOgnlSecurityManagerOnInit;
    static {
        boolean initialFlagState = false;
        try {
            final String propertyString = System.getProperty(OGNL_SECURITY_MANAGER);
            if (propertyString != null && propertyString.length() > 0) {
                initialFlagState = OGNL_SM_FORCE_DISABLE_ON_INIT.equalsIgnoreCase(propertyString);
            }
        } catch (Exception ex) {
            // Unavailable (SecurityException, etc.)
        }
        _disableOgnlSecurityManagerOnInit = initialFlagState;
    }
```

因此在jvm参数中添加`-Dognl.security.manager=forceDisableOnInit`即可在初始化时禁用
OGNL SecurityManager。

由于目前项目并没有配置`ognl.security.manager`属性，`if (System.getProperty("ognl.security.manager") == null)`始终为true，大量无效调用`System.getProperty("ognl.security.manager")`。因此修改应用的jvm配置添加`-Dognl.security.manager=forceDisableOnInit`即可解决高并发下OGNL获取`ognl.security.manager`属性导致的性能问题。


> **<font color=red>注意：OGNL SecurityManager处于关闭状态，为保证系统安全，在编写动态SQL时应该避免在 OGNL 表达式中使用用户可控的参数并结合其它手段防止恶意注入</font>**


参考资料：
- https://github.com/orphan-oss/ognl/blob/OGNL_3_3_0/src/main/java/ognl/OgnlRuntime.java#L1236

