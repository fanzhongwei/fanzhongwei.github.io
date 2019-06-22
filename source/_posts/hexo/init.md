---
title: Hexo搭建个人博客
date: 2019-06-22
tags: 
	- Hexo
	- 个人博客
categories:
	- Hexo
---

之前基于Hexo搭建了个人博客网站，最近换了个Linux系统，差不多又重新搭建了一遍hexo，而且还遇到了许多问题，所以在这里记录一下hexo的搭建方法。

![ZpxeNd.png](https://s2.ax1x.com/2019/06/22/ZpxeNd.png)

<!-- more -->

# 什么是Hexo

Hexo 是一个快速、简洁且高效的博客框架。Hexo 使用 Markdown（或其他渲染引擎）解析文章，在几秒内，即可利用靓丽的主题生成静态网页。

# 安装前提

## Node.js (Should be at least nodejs 6.9)

直接使用已编译好的包
Node 官网已经把 linux 下载版本更改为已编译好的版本了，我们可以直接下载解压后使用：
```
wget https://nodejs.org/dist/v10.16.0/node-v10.16.0-linux-x64.tar.xz    // 下载
tar xf  node-v10.16.0-linux-x64.tar.xz       // 解压
cd node-v10.16.0-linux-x64/                  // 进入解压目录
./bin/node -v                               // 执行node命令 查看版本
v10.16.0
```
也可以进入Node官网下载最新版本：https://nodejs.org/

解压文件的 bin 目录底下包含了 node、npm 等命令，我们可以使用 ln 命令来设置软连接：

```
ln -s /usr/software/node-v10.16.0-linux-x64/bin/npm   /usr/local/bin/ 
ln -s /usr/software/node-v10.16.0-linux-x64/bin/node   /usr/local/bin/
```

## Git

这个就不用多介绍了：sudo apt-get install git

## 安装Hexo

```
$ npm install -g hexo-cli
```

安装后会执行 hexo，会发现找不到命令，把hexo加入到软连接即可：
```
ln -s /usr/software/node-v10.16.0-linux-x64/lib/node_modules/hexo-cli/bin/hexo   /usr/local/bin/
```

# 建站

参考官方文档即可：https://hexo.io/zh-cn/docs/setup

# 主题配置

参考官方文档即可：https://theme-next.org/

# 启动

hexo server