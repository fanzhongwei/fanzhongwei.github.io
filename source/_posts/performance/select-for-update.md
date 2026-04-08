---
title: 性能优化-高效生成全局唯一自增序列
date: 2024-09-18
tags:
  - 性能优化
  - 数据库
categories:
  - 性能优化
---

# 性能优化-高效生成全局唯一自增序列

如何高效地生成全局唯一自增序列，一个设置让性能提升100倍。

## 背景

系统上线前性能测试时，对生成具有业务含义的全局唯一且自增的序列进行压测；200并发，4个8C16G的应用节点，压测结果如下：

| 类名名 | 方法名 | 调用次数 | avg | min | max | 90% pct | 95% pct | 99% pct |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LockUtils | forUpdateLockAndRun | 5505 | 3821 | 11 | 35020 | 9110 | 11014 | 18045 |
| LockExecutor | executeLock | 5505 | 36 | 6 | 389 | 88 | 122 | 208 |

这结果可以说是惨不忍睹～～～

> 如何获取方法级别的性能测试报告，详情请查看：[性能优化利器-JavaAgent](https://mp.weixin.qq.com/s/VQTsvtWocQx7veO3saNUqA)

## 生成全局唯一自增序列

生成具有业务含义的全局唯一且自增的序列，是采用SELECT FOR UPDATE方案实现，生成逻辑：
- 1、`select for update`获取数据库序列配置的行锁
- 2、对序列配置进行自增操作
- 3、更新序列配置
- 如果任何一步失败则进行重试，最多重试三次

核心源码如下：
```java
    private static TransactionDefinition TRANSACTION_DEFINITION = new DefaultTransactionDefinition();

    private static void forUpdateLockAndRun(Class<IEntity> lockEntityClass, QueryWrapper<IEntity> selectForUpdate, LockExecutor lockExecutor, int retryTimes) {
        if (retryTimes >= 3) {
            throw new ResourceUpdateFailedException("tryForUpdateLockAndRun失败，重试次数已达到上限，请稍后再试");
        }
        BaseMapper<IEntity> mapper = DB_OPERATE_SERVICE.getMapperByEntityClass(lockEntityClass);
        TransactionStatus transactionStatus = TRANSACTION_MANAGER.getTransaction(TRANSACTION_DEFINITION);
        IEntity lockData = null;
        try {
            selectForUpdate.last(" for update");
            lockData = mapper.selectOne(selectForUpdate);
        } catch (Exception e) {
            log.error("tryForUpdateLockAndRun异常，获取锁失败，进行重试", e);
            TRANSACTION_MANAGER.rollback(transactionStatus);
            forUpdateLockAndRun(lockEntityClass, selectForUpdate, lockExecutor, retryTimes + 1);
            return;
        }
        Assert.notNull(lockData, "tryForUpdateLockAndRun异常，未获取到需要锁定的数据，无法进行重试");
        try {
            // 对lockData进行自增操作
            IEntity newLockData = lockExecutor.executeLock(lockData);
            if (null != newLockData) {
                selectForUpdate.last("");
                mapper.update(newLockData, selectForUpdate);
            }
            TRANSACTION_MANAGER.commit(transactionStatus);
        } catch (Exception e) {
            log.error("tryForUpdateLockAndRun获取到锁，但更新数据失败，进行重试", e);
            TRANSACTION_MANAGER.rollback(transactionStatus);
            forUpdateLockAndRun(lockEntityClass, selectForUpdate, lockExecutor, retryTimes + 1);
        }
    }

    public static interface LockExecutor {
        IEntity executeLock(IEntity lockData);
    }
```



### 什么是SELECT FOR UPDATE

`SELECT FOR UPDATE`是由数据库（MySQL、PostgreSQL 和 Oracle等）提供的一种事务锁定机制，用于在事务中锁定所选的行，以防止其他事务对这些行进行修改。

当一个事务执行`SELECT FOR UPDATE`语句时，数据库会对查询结果集中的每一行进行加锁。这些锁会一直保持到事务提交或回滚时才会释放。在此期间，其他事务无法对这些被锁定的行进行修改或删除操作，从而确保了数据的一致性。

SELECT FOR UPDATE的实际应用有：
- 生成自增全局唯一标识：生成具有业务含义的全局唯一且自增的序列，避免生成重复序列。
- 库存管理：确保在扣减库存时，只有一个事务能够成功更新库存数量，避免超卖问题。
- 账户余额更新：在金融系统中，账户余额的更新需要确保数据的一致性。
- 订单处理：锁定订单状态，确保订单状态的更新按照预期的顺序执行，避免并发问题


## 性能问题分析过程

通过方法的性能测试报告中可以发现forUpdateLockAndRun方法执行时间特别长，但executeLock方法的执行时间又特别短，同时查看应用的jbdc日志发现`select for update`的sql执行时间居然达到35秒：
```sql
select * from t_wybs_scpz where key='xxx_wybs' for update ##^^## select * from t_wybs_scpz where key=? for update
 {executed in 35004 msec}
{resultSet rows 1, build in 0 msec}
```

### 怀疑缺少索引

查看`t_wybs_scpz`表结构发现有索引，分析sql的执行计划也确实走了索引：

```sql
explain 
select * from t_wybs_scpz where key='xxx_wybs' for update

=================================================================================================
|ID|OPERATOR                        |NAME                                 |EST.ROWS|EST.TIME(us)|
-------------------------------------------------------------------------------------------------
|0 |MATERIAL                        |                                     |1       |32          |
|1 |└─DISTRIBUTED FOR UPDATE        |                                     |1       |32          |
|2 |  └─DISTRIBUTED TABLE RANGE SCAN|T_WYBS_SCPZ(I_WYBS_SCPZ_KEY)         |1       |32          |
=================================================================================================
```

因此，可以排除缺少索引的嫌疑。

### 怀疑FOR UPDATE锁表

虽然`SELECT FOR UPDATE`是只索引查询返回的行，但是在某些情况下还是会锁表：

#### 没有合适的索引或索引未使用

如果查询条件没有使用索引，或者查询的列没有合适的索引，数据库将进行**全表扫描**。数据库进行全表扫描时，需要先将数据加载到内存然后进行匹配（如果某行数据被锁住，这一步就会阻塞），因此即使只锁住一行数据也会表现出锁表的现象。

通过上面的sql执行计划可以确定索引已生效，排除这种可能。

#### 锁升级

在某些数据库（如 Oracle）中，锁机制是行级别的。但如果事务中的行锁数量过多，数据库可能会触发锁升级，将行锁升级为表锁。锁升级的发生是为了减少系统开销，但可能会导致表级别的锁定。

通过jdbc日志`{resultSet rows 1, build in 0 msec}`发现，只返回了一行数据，排除这种可能。

综上所述，基本可以排除锁表的嫌疑。

### 怀疑事务长时间未结束

`forUpdateLockAndRun`方法中`lockExecutor.executeLock(lockData)`执行时间非常短（平均只有36ms），也就是说从获取到锁之后到事务结束平均耗时只有36ms。

那么是不是就可以排除事务长时间未结束的嫌疑呢，我们可以本地代码调试验证下：
1. 在`IEntity newLockData = lockExecutor.executeLock(lockData);`添加断点，然后在数据库查询`select * from t_wybs_scpz where key='xxx_wybs' for update`，发现被锁住不能返回结果，符合预期。
2. 在`forUpdateLockAndRun`方法执行结束后，然后在数据库查询`select * from t_wybs_scpz where key='xxx_wybs' for update`，发现被锁住不能返回结果，**不符合预期**。

因此可以判断的确是事务长时间未结束导致数据库行锁长时间未释放。

**为什么`forUpdateLockAndRun`方法中事务被commit了，但是事务仍然没有结束呢？**


查阅源码发现事务的定义`private static TransactionDefinition TRANSACTION_DEFINITION = new DefaultTransactionDefinition();`，其中使用事务的传播机制默认使用的`PROPAGATION_REQUIRED`，通过查阅`spring-tx`中`TransactionDefinition`的源码中对其的定义如下：
```java
	/**
	 * Support a current transaction; create a new one if none exists.
	 * Analogous to the EJB transaction attribute of the same name.
	 * <p>This is typically the default setting of a transaction definition,
	 * and typically defines a transaction synchronization scope.
	 */
	int PROPAGATION_REQUIRED = 0;
```
也就是说`forUpdateLockAndRun`方法中`TransactionStatus transactionStatus = TRANSACTION_MANAGER.getTransaction(TRANSACTION_DEFINITION);`开启事务的逻辑为：创建一个事务，如果当前已存在事务则加入到这个事务中。

通过查看`forUpdateLockAndRun`的上层调用链，发现在上层调用链的入口果然也在事务中：
```java
@Transactional(rollbackFor = Exception.class)
public void saveData() {
    ...
    
    // 下层调用forUpdateLockAndRun
    createWybs()
    
    ...
}
```

至此终于找到了`SELECT FOR UPDATE`慢的原因了：由于`forUpdateLockAndRun`方法中的`SELECT FOR UPDATE`<font color=red>必须要等到外层事务结束后才能释放数据库的行锁</font>，因此高并发下请求`forUpdateLockAndRun`方法就出现了大量排队的情况。


## 解决方案

将事务定义的传播方式设置为`PROPAGATION_REQUIRES_NEW`：创建一个新事务，如果当前存在事务，则把当前事务挂起，`private static TransactionDefinition TRANSACTION_DEFINITION = new DefaultTransactionDefinition(TransactionDefinition.PROPAGATION_REQUIRES_NEW);`

调整完成后再次进行压测，结果如下：

| 类名名 | 方法名 | 调用次数 | avg | min | max | 90% pct | 95% pct | 99% pct |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LockUtils | forUpdateLockAndRun | 7248 | 37 | 14 | 523 | 51 | 106 | 271 |
| LockExecutor | executeLock | 7248 | 22 | 6 | 251 | 24 | 51 | 107 |

`forUpdateLockAndRun`的平均耗时从3821ms提升到37ms，性能提升**100倍**。

注意：**将事务定义的传播方式设置为`PROPAGATION_REQUIRES_NEW`后，锁定的数据修改是单独提交的，如果`forUpdateLockAndRun`执行成功后（修改已提交到数据库）上层事务处理失败回滚时需要由上层调用方判断`forUpdateLockAndRun`中修改的数据是否需要回滚，如果需要回滚则需要手动回滚。**

如果锁的竞争不是非常大，可以考虑使用乐观锁代替`SELECT FOR UPDATE`。乐观锁可以通过版本号或时间戳机制来实现并发控制，避免了悲观锁的锁竞争问题。


> 这里补充一下Spring的7种事务传播机制：
> 1. REQUIRED（默认）：如果当前存在事务，则加入该事务；如果当前没有事务，则创建一个新的事务。
> 2. SUPPORTS：如果当前存在事务，则加入该事务；如果当前没有事务，则以非事务的方式继续运行。
> 3. MANDATORY：如果当前存在事务，则加入该事务；如果当前没有事务，则抛出异常。
> 4. REQUIRES_NEW：创建一个新的事务,如果当前存在事务,则把当前事务挂起。
> 5. NOT_SUPPORTED：以非事务方式运行，如果当前存在事务，则把当前事务挂起。
> 6. NEVER：以非事务方式运行，如果当前存在事务，则抛出异常。
> 7. NESTED：如果当前存在事务，则创建一个事务作为当前事务的嵌套事务来运行；如果当前没有事务，则该取值等价于REQUIRED
