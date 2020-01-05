---
title: springboot + jpa + h2 单元测试实战
date: 2019-07-03
tags: 
	- springboot
	- jpa
	- h2
	- 单元测试
categories:
	- 单元测试
---

最近需要开发一个组件，里面会有数据库操作，但由于该组件是单独开发没有实际的数据库，数据库后期会创建到集成该组件的业务系统里面。所以想到用内存数据来做测试，也避免了拿真实数据库作测试时留下垃圾数据，而且速度还比较快。

![ZtTvnI.png](https://s2.ax1x.com/2019/07/03/ZtTvnI.png)

<!-- more -->

经历了一顿操作，终于搭好了单元测试环境。

# POM文件
```xml
	<dependencies>
		<dependency>
			<groupId>org.projectlombok</groupId>
			<artifactId>lombok</artifactId>
		</dependency>
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-starter-data-jpa</artifactId>
		</dependency>

		<!-- test dependency -->
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-starter-test</artifactId>
			<scope>test</scope>
		</dependency>
		<dependency>
			<groupId>com.h2database</groupId>
			<artifactId>h2</artifactId>
			<scope>test</scope>
		</dependency>
	</dependencies>

	<dependencyManagement>
		<dependencies>
			<dependency>
				<!-- Import dependency management from Spring Boot -->
				<groupId>org.springframework.boot</groupId>
				<artifactId>spring-boot-dependencies</artifactId>
				<version>2.1.2.RELEASE</version>
				<type>pom</type>
				<scope>import</scope>
			</dependency>
		</dependencies>
	</dependencyManagement>
```
# 配置文件application.yml
```yaml
spring:
  h2:
    console:
      enabled: true
      path: /console
      settings:
        web-allow-others: true
        trace: false
  datasource:
    name: dataSource
    platform: h2
    driver-class-name: org.h2.Driver
    url: jdbc:h2:mem:test;MODE=PostgreSQL;DB_CLOSE_DELAY=-1;DATABASE_TO_UPPER=false;
    username: sa
    password: 123456
    schema:
      - classpath:sql/create/01.CS_SCHEMA.sql
      - classpath:sql/create/02.CT_TABLE.sql
    data:
      - classpath:sql/data/02.I_T_TEST.sql
  jpa:
    show-sql: true
    hibernate:
      ddl-auto: none
    database-platform: org.hibernate.dialect.H2Dialect
```
# 创建DO层
- Entity
```java
@Entity
@Table(name = "t_test", schema = "test")
@Data
public class TestDO implements Serializable {
    private static final long serialVersionUID = 1L;
    
    @Id
    @Column(name = "id")
    private String id;
    
    // columns定义
    // ···
}
```
- Repository
```java
@Repository
public interface TestRepository extends JpaRepository<TestDO,String> {

}
```
JPA的使用和配置参考淋哥的：[Spring data jpa使用总结](http://artery.thunisoft.com/posts/detail/051df2202436454fb14379fe3e88ab7b)

# 单元测试
```java
@RunWith(SpringRunner.class)
@SpringBootTest(classes =TestApplication.class)
public class TestRepositoryTest {

    @Resource
    private TestRepository testRepository;

    @Test
    public void test_table_should_have_one_record(){
        Assert.assertEquals(1, testRepository.count());
    }
}
```
TimeLimitTestApplication代码如下：
```java
@SpringBootApplication
@EnableJpaRepositories(basePackages = "com.teddy.repository")
@EntityScan(basePackages = "com.teddy.entity")
public class TestApplication {
}
```
# 遇到的问题
- table not found
  h2数据库初始化的时候，已经执行了初始化脚本，但是执行单元测试时找不到表，经过排查，发现创建数据库脚本如下：
```sql
set search_path to test;
commit;

drop table if exists t_test;
create table t_test(
   ···
);
```
该脚本在真实数据库中执行没有任何问题，但是在h2数据库中，并不能将表正确的创建到test模式中，而是创建到PUBLIC模式中了，导致找不到表。

修改脚本如下：
```java
set search_path to test;
commit;

drop table if exists test.t_test;
create table test.t_test(
   ···
);
```
即可解决该问题。
- schema not found
由于JPA不区分大小写，注解里面配置的都会转成小写（可以通过配置：
spring.jpa.hibernate.naming.physical-strategy=org.hibernate.boot.model.naming.PhysicalNamingStrategyStandardImpl即可解决表名，但是schema都是小写）。而H2数据库是区分大小写的，因此可能导致schema not found。

只要统一大小写即可处理。