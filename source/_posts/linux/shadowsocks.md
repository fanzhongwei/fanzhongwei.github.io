---
title: Linux 科学上网
date: 2019-06-20
tags: 
	- Linux
	- Deepin
	- SSR
	- ShadowsocksR
categories:
	- Linux
---

最近因为各种原因，从Windows转Linux，之前在Windows上用得非常爽的SSR客户端，但是在应用商店找了很久，都不好使。
最终找到electron-ssr，和Windows上的差不多。

![VvOOl4.png](https://s2.ax1x.com/2019/06/20/VvOOl4.png)

<!-- more -->

# ShadowsocksR跨平台客户端
这是一个跨平台（支持Windows MacOS Linux系统）的ShadowsocksR客户端桌面应用，它功能丰富，支持windows版大部分功能，更有更多人性化功能。它是开源的，它来源于开源，回馈以开源。

功能特色

- 支持手动添加配置
- 支持服务器订阅更新，复制该地址测试
- 支持二维码扫描(请确保屏幕中只有一个有效的二维码)，扫描该二维码测试
- 支持从剪贴板复制、从配置文件导入等方式添加配置
- 支持复制二维码图片、复制SSR链接(右键应用内二维码，点击右键菜单中的复制)
- 支持通过点击ss/ssr链接添加配置并打开应用(仅Mac和Windows)
- 支持切换系统代理模式:PAC、全局、不代理
- 内置http_proxy服务，可在选项中开启或关闭
- 支持配置项变更
- 更多功能尽在任务栏菜单中

# 下载

该软件的作者已经将其从GitHub上删除了，不再维护了，不过还好找到了备份，传送门：https://github.com/qingshuisiyuan/electron-ssr-backup/releases

Deepin、Ubuntu系列下载[electron-ssr-0.2.6.deb](https://github.com/qingshuisiyuan/electron-ssr-backup/releases/download/v0.2.6/electron-ssr-0.2.6.deb)

# 安装和配置

sudo dpkg -i electron-ssr-0.2.6.deb

配置很简单，和Windows上的SSR客户端差不多，拷贝SSR的订阅连接，更新，然后选择喜欢的节点即可。

![Vvjhaq.png](https://s2.ax1x.com/2019/06/20/Vvjhaq.png)