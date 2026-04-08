---
title: 性能优化-解决MyBatis高并发下OGNL反射调用方法的锁竞争
date: 2025-12-31
tags:
  - 性能优化
  - MyBatis
  - OGNL
categories:
  - 性能优化
---

# 性能优化-解决MyBatis高并发下OGNL反射调用方法的锁竞争

> 摘要： 继解决OGNL安全属性检查的性能问题后，线上服务再次因MyBatis查询阻塞而超时。分析发现，近千个线程阻塞在OgnlRuntime.invokeMethod方法，竞争同一个Method对象的锁。根本原因在于，MyBatis-Plus动态SQL在解析时，会高并发地通过反射调用Wrapper对象的固定几个Getter方法（如getSqlSegment）。OGNL为缓存每个方法的访问权限，在首次检查时使用了synchronized(method)，导致严重锁竞争。解决方案是为其缓存机制引入“双重检查锁定”优化，避免后续调用仍需同步，从而根治此瓶颈。该修复已向OGNL社区提交并已于3.4.10版本发布。

## 背景

经过上一篇文章，[性能优化-巧解MyBatis高并发下OGNL安全检查导致的全局锁瓶颈.md](https://share.note.youdao.com/s/cVnB3WPM)，我们成功解决了OGNL高并发调用`System.getProperty("ognl.security.manager")`导致的性能瓶颈。

但好景不长，没过几天线上环境又频繁报接口响应超时，很多节点同时报`[HSF-Provider] HSF thread pool is full.`，dump线程信息进行分析，发现大部分线程还是卡在mybatis查询数据库，这又是为什么呢？


## 问题排查过程

### 程堆栈分析

于是我们又dump线程信息进行分析，结果还是`OgnlRuntime`这个类导致，不过这次有981个线程阻塞在`org.apache.ibatis.ognl.OgnlRuntime.invokeMethod(OgnlRuntime.java:1151)`，具体线程堆栈信息如下：

```
# 980个线程被阻塞
"default-17571" #91915 prio=5 os_prio=0 tid=0x00007f7b7c05d800 nid=0x167f9 waiting for monitor entry [0x00007f757f772000]
   java.lang.Thread.State: BLOCKED (on object monitor)
	at org.apache.ibatis.ognl.OgnlRuntime.invokeMethod(OgnlRuntime.java:1151)
	- waiting to lock <0x00000004a55aaf48> (a java.lang.reflect.Method)
	at org.apache.ibatis.ognl.OgnlRuntime.getMethodValue(OgnlRuntime.java:2146)
	at org.apache.ibatis.ognl.ObjectPropertyAccessor.getPossibleProperty(ObjectPropertyAccessor.java:66)
	at org.apache.ibatis.ognl.ObjectPropertyAccessor.getProperty(ObjectPropertyAccessor.java:160)
	at org.apache.ibatis.ognl.OgnlRuntime.getProperty(OgnlRuntime.java:3356)
	...

# 获取到锁的线程
"HSFBizProcessor-DEFAULT-6-thread-5179" #90650 daemon prio=10 os_prio=0 tid=0x00007f794c319000 nid=0x16214 waiting for monitor entry [0x00007f758366e000]
   java.lang.Thread.State: BLOCKED (on object monitor)
	at org.apache.ibatis.ognl.OgnlRuntime.invokeMethod(OgnlRuntime.java:1151)
	- locked <0x00000004a55aaf48> (a java.lang.reflect.Method)
	at org.apache.ibatis.ognl.OgnlRuntime.getMethodValue(OgnlRuntime.java:2146)
	at org.apache.ibatis.ognl.ObjectPropertyAccessor.getPossibleProperty(ObjectPropertyAccessor.java:66)
	at org.apache.ibatis.ognl.ObjectPropertyAccessor.getProperty(ObjectPropertyAccessor.java:160)
	at org.apache.ibatis.ognl.OgnlRuntime.getProperty(OgnlRuntime.java:3356)
	...
```


### 源码分析

从上面的线程堆栈信息可以看到所有的线程都阻塞在`org.apache.ibatis.ognl.OgnlRuntime.invokeMethod(OgnlRuntime.java:1151)`，看看源码这里在干啥呢：

```java

    public static Object invokeMethod(Object target, Method method, Object[] argsArray)
            throws InvocationTargetException, IllegalAccessException
    {
        boolean syncInvoke;
        boolean checkPermission;
        Boolean methodAccessCacheValue;
        Boolean methodPermCacheValue;

        ...

        // only synchronize method invocation if it actually requires it
        // 这里就是堆栈中的1151行，对method加锁，然后将method的方法可见性和方法执行权限缓存
        synchronized(method) {
            methodAccessCacheValue = _methodAccessCache.get(method);
            if (methodAccessCacheValue == null) {
                // 检查方法是否是public的
                if (!Modifier.isPublic(method.getModifiers()) || !Modifier.isPublic(method.getDeclaringClass().getModifiers()))
                {
                    // 检查是否是可访问的
                    if (!(((AccessibleObject) method).isAccessible()))
                    {
                        methodAccessCacheValue = Boolean.TRUE;
                        _methodAccessCache.put(method, methodAccessCacheValue);
                    } else
                    {
                        methodAccessCacheValue = Boolean.FALSE;
                        _methodAccessCache.put(method, methodAccessCacheValue);
                    }
                } else
                {
                    methodAccessCacheValue = Boolean.FALSE;
                    _methodAccessCache.put(method, methodAccessCacheValue);
                }
            }
            // 如果不可访问标记为同步执行
            syncInvoke = Boolean.TRUE.equals(methodAccessCacheValue);

            methodPermCacheValue = _methodPermCache.get(method);
            if (methodPermCacheValue == null) {
                if (_securityManager != null) {
                    try
                    {
                        // 检查方法执行权限
                        _securityManager.checkPermission(getPermission(method));
                        methodPermCacheValue = Boolean.TRUE;
                        _methodPermCache.put(method, methodPermCacheValue);
                    } catch (SecurityException ex) {
                        methodPermCacheValue = Boolean.FALSE;
                        _methodPermCache.put(method, methodPermCacheValue);
                        throw new IllegalAccessException("Method [" + method + "] cannot be accessed.");
                    }
                }
                else {
                    methodPermCacheValue = Boolean.TRUE;
                    _methodPermCache.put(method, methodPermCacheValue);
                }
            }
            checkPermission = Boolean.FALSE.equals(methodPermCacheValue);
        }

        Object result;

        if (syncInvoke) //if is not public and is not accessible
        {
            // 加锁同步反射调用method，因为需要先将方法设置为可访问，反射调用完，再将其设置为不可访问
            // 如果不加锁，并发时可能导致方法反射调用失败
            // 线程A -> _accessibleObjectHandler.setAccessible(method, false);
            // 线程B -> result = invokeMethodInsideSandbox(target, method, argsArray);
            synchronized(method)
            {
                if (checkPermission)
                {
                    try
                    {
                        _securityManager.checkPermission(getPermission(method));
                    } catch (SecurityException ex) {
                        throw new IllegalAccessException("Method [" + method + "] cannot be accessed.");
                    }
                }

                _accessibleObjectHandler.setAccessible(method, true);
                try {
                    result = invokeMethodInsideSandbox(target, method, argsArray);
                } finally {
                    _accessibleObjectHandler.setAccessible(method, false);
                }
            }
        } else
        {
            if (checkPermission)
            {
                try
                {
                    _securityManager.checkPermission(getPermission(method));
                } catch (SecurityException ex) {
                    throw new IllegalAccessException("Method [" + method + "] cannot be accessed.");
                }
            }

            result = invokeMethodInsideSandbox(target, method, argsArray);
        }

        return result;
    }

```



> 完整源码请查看：[https://github.com/orphan-oss/ognl/blob/OGNL_3_3_0/src/main/java/ognl/OgnlRuntime.java#L1151](https://github.com/orphan-oss/ognl/blob/OGNL_3_3_0/src/main/java/ognl/OgnlRuntime.java#L1151)
>
> 我们项目mybatis的版本是3.5.9，对应的ognl版本是3.3.0，从`/mybatis-3.5.9.jar!/META-INF/maven/ognl/ognl/pom.xml`中可以看到对应的版本，mybatis是将ognl的class直接构建到了mybatis的jar包中了。


从上面的源码分析结合堆栈分析，所有的线程都阻塞在1151行`synchronized(method) {`，等待获取`method`的访问权限和执行权限，证明有大量线程要去调用同一个`method`对象，这是为什么呢？


### 问题剖析

为什么有大量线程在mybatis的查询中都在反射调用相同的方法呢，这就要从MyBatis-Plus说起了，项目使用的是MyBatis-Plus做动态SQL拼装，例如下面的动态SQL：

```java
LambdaQueryWrapper<User> wrapper = new LambdaQueryWrapper<>();
wrapper.eq(User::getName, "A")      
       .eq(User::getAge, 20)        
       .like(User::getEmail, "a")   
       .gt(User::getScore, 60)      
       .orderByAsc(User::getId);    
       
   service.list(wrapper);
```

实际上调用的是`com.baomidou.mybatisplus.core.mapper.BaseMapper.selectList`方法，其动态SQL的XML如下:
```xml
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<script>
    <if test="ew != null and ew.sqlFirst != null">
    ${ew.sqlFirst}
    </if>
     SELECT 
    <choose>
        <when test="ew != null and ew.sqlSelect != null">
        ${ew.sqlSelect}
        </when>
        <otherwise>ID,NAME,AGE,EMAIL,SCORE</otherwise>
    </choose>
     FROM user 
    <if test="ew != null">
        <where>
            <if test="ew.entity != null">
                <!--  -->
                <if test="ew.entity['id'] != null"> AND ID=#{ew.entity.idB}</if>
            </if>
            <if test="ew.sqlSegment != null and ew.sqlSegment != '' and ew.nonEmptyOfWhere">
                <if test="ew.nonEmptyOfEntity and ew.nonEmptyOfNormal"> AND</if>
                ${ew.sqlSegment}
            </if>
        </where>
        <if test="ew.sqlSegment != null and ew.sqlSegment != '' and ew.emptyOfWhere">
         ${ew.sqlSegment}
        </if>
    </if>
    <if test="ew != null and ew.sqlComment != null">
    ${ew.sqlComment}
    </if>
</script>
```

> 其中`BaseMapper.selectList`方法的SQL脚本是由`com.baomidou.mybatisplus.core.injector.methods.SelectList`注入的。
> SQL注入器的详细文档请参考：https://baomidou.com/guides/sql-injector/

从上面的动态SQL分析可以发现，**每一个动态SQL在mybatis解析OGNL表达式时都必然会通过反射获取`Wrapper`对象这些属性的值：`sqlFirst`、`sqlSelect`、`sqlSegment`、`nonEmptyOfEntity`、`sqlComment`**。再高并发的时候，都会通过反射调用这些属性对应的get方法获取这些属性的值，那么`synchronized(method)`锁的都是相同的方法也就不奇怪了。


## 解决方案

从上面的线程堆栈以及源码分析，我们知道了问题产生的原因，那么我们将`synchronized(method)`锁的的竞争降低就可以解决问题，于是我们可以这样修改`Ognl`的源码，给`method`加上`Double null ckeck`：

```java
    public static Object invokeMethod(Object target, Method method, Object[] argsArray)
            throws InvocationTargetException, IllegalAccessException {
        boolean syncInvoke;
        Boolean methodAccessCacheValue;

        ...

        // only synchronize method invocation if it actually requires it
        methodAccessCacheValue = _methodAccessCache.get(method);
        // double null check to avoid synchronizing on the method
        if (methodAccessCacheValue == null) {
            synchronized (method) {
                methodAccessCacheValue = _methodAccessCache.get(method);
                if (methodAccessCacheValue == null) {
                    if (!Modifier.isPublic(method.getModifiers()) || !Modifier.isPublic(method.getDeclaringClass().getModifiers())) {
                        var obj = Modifier.isStatic(method.getModifiers()) ? null : target;
                        if (method.canAccess(obj)) {
                            methodAccessCacheValue = Boolean.FALSE;
                            _methodAccessCache.put(method, methodAccessCacheValue);
                        } else {
                            methodAccessCacheValue = Boolean.TRUE;
                            _methodAccessCache.put(method, methodAccessCacheValue);
                        }
                    } else {
                        methodAccessCacheValue = Boolean.FALSE;
                        _methodAccessCache.put(method, methodAccessCacheValue);
                    }
                }
                syncInvoke = Boolean.TRUE.equals(methodAccessCacheValue);

                _methodPermCache.putIfAbsent(method, Boolean.TRUE);
            }
        } else {
            syncInvoke = Boolean.TRUE.equals(methodAccessCacheValue);
        }
        ...
    }
```

> 上面是基于[https://github.com/orphan-oss/ognl](https://github.com/orphan-oss/ognl)最新的源码修改，和本文项目中用到的`3.3.0`版本有细微差异，但问题也同样存在。


经过如上修改`OgnlRuntime#invokeMethod`源码升级项目后，再也没出现过`OgnlRuntime.invokeMethod`阻塞的问题了。


具体的issue和Pull request请查看：
- [https://github.com/mybatis/mybatis-3/issues/3589](https://github.com/mybatis/mybatis-3/issues/3589)
- [https://github.com/orphan-oss/ognl/pull/521](https://github.com/orphan-oss/ognl/pull/521)

OGNL社区已采纳，已合并到3.4.10版本发布。


参考资料：
- OGNL 源码：[https://github.com/orphan-oss/ognl/blob/OGNL_3_3_0/src/main/java/ognl/OgnlRuntime.java#L1151](https://github.com/orphan-oss/ognl/blob/OGNL_3_3_0/src/main/java/ognl/OgnlRuntime.java#L1151)

- MyBatis-Plus 官方文档（SQL注入器）：[https://baomidou.com/guides/sql-injector/](https://baomidou.com/guides/sql-injector/)

- 向MyBatis社区提交的Issue：[https://github.com/mybatis/mybatis-3/issues/3589](https://github.com/mybatis/mybatis-3/issues/3589)

- 向OGNL社区提交的Pull Request：[https://github.com/orphan-oss/ognl/pull/521](https://github.com/orphan-oss/ognl/pull/521)


