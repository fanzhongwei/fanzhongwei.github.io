---
title: MCP网关
date: 2025-05-14
tags:
  - AI
  - MCP
  - 网关
categories:
  - AI
---

# MCP网关

类似开源项目：
https://github.com/mcp-ecosystem/mcp-gateway


技术选型：
- 后端：
    - SpringBoot 3
    - spring-ai-mcp-server-webmvc-spring-boot-starter
    - PostgreSql
    - MybatisPlus
    - druid管理数据库连接
    - flyway管理数据库脚本，脚本放在resources/db目录下，初始化版本为V0.0
- 前端：
    - vue3
    - 使用vite进行包管理
- 数据库：脚本放在resources/db目录下，初始化版本为V0.0
    - t_user：存储用户信息
    - t_mcp_project：存储项目信息
    - t_mcp_project_user：存储项目中的人员信息，关联t_user
    - t_mcp_tools：存储代理的tools，关联到每个具体的项目信息


后端目录：server
前端目录：web

实现功能：
- 登录页面：输入用户名密码进行登录，支持手动注册用户


