---
title: Deepin install Typora
date: 2019-10-22
tags: 
	- Linux
	- Deepin
	- Markdown
	- Typora
categories:
	- Linux
---

在Deepin系统商店中就有携带Typora，提是使用深度源，但是大家一般都换成阿里云等速度比较快的源。按照官方文档安装也是一大堆问题，后来采用Linux Mint的安装方式完美解决

![Typora.png](https://www.typora.io/img/theme-prev/Snip20141101_3.png)

<!-- more -->

```shell
# or use
# sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys BA300B7755AFCFAE
wget -qO - https://typora.io/linux/public-key.asc | sudo apt-key add -

# add Typora's repository
echo -e "\ndeb https://typora.io/linux ./" | sudo tee -a /etc/apt/sources.list
sudo apt-get update

# install typora
sudo apt-get install typora
```

注：不要使用官方推荐的Deb和Ubuntu的那个安装方法，采用Linux Mint的。

