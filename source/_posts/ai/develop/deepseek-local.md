---
title: DeepSeek本地部署
date: 2025-04-30
tags:
  - AI
  - 部署
categories:
  - AI
---

# DeepSeek本地部署

作为一款现象级的Ai产品，DeepSeek用户量暴增，服务器又被攻击，使用DeepSeek，经常出现服务器繁忙。

将DeepSeek部署在本地电脑就方便很多，选择对应的模型来下载，1.5b、7b、8b、14b、32b、70b或671b，这里有很多版本可选，模型越大，要求电脑内存、显卡等的配置越高。DeepSeek部署在本地电脑上部署，有些不方便公开的数据，比如实验数据、企业内部数据，可以被本地的大模型安全地使用了。

## 下载安装 Ollama

访问Ollama官网：https://ollama.com/download

选择对应操作系统进行安装，这里以linux为例：

```
curl -fsSL https://ollama.com/install.sh | sh
```

如果下载较慢，可以考虑使用docker方式安装：https://hub.docker.com/r/ollama/ollama


- Install the NVIDIA Container Toolkit packages
```shell
sudo apt-get install -y nvidia-container-toolkit
```

- Configure Docker to use Nvidia driver
```
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

启动容器

```
docker run -d --gpus=all --restart always -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
```

## 安装DeepSeek大模型

```
docker exec -it ollama ollama run deepseek-r1:8b
```

模型大小如何选择：


| 模型大小 | 参数量 | 显存需求 (GPU) | 内存需求 | 适用场景 |
| --- | --- | --- | --- | --- |
| 1.5B | 15亿 | 2～4 GB | 8 GB | 低端设备，轻量推理 |
| 7B | 70亿 | 8～12 GB | 16 GB | 中端设备，通用推理 |
| 8B | 80亿 | 10～16 GB | 16 ~ 32 GB | 中高端设备，高性能推理 |
| 14B | 140亿 | 16～24 GB | 32 GB | 高端设备，高性能推理 |
| 32B | 320亿 | 32～48 GB | 64 GB | 高端设备，专业推理 |
| 70B | 700亿 | 64 GB+ | 128 GB | 顶级设备，大规模推理 |
| 761B | 6710亿 | 多GPU（80 GB+） | 256 GB+ | 超大规模推理，分布式计算 |

然后就可以开启对话了：

```shell
docker exec -it ollama ollama run deepseek-r1:8b
pulling manifest 
pulling 6340dc3229b0... 100% ▕█████████████████████ 4.9 GB                         
pulling 369ca498f347... 100% ▕█████████████████████ 387 B                         
pulling 6e4c38e1172f... 100% ▕█████████████████████ 1.1 KB                         
pulling f4d24e9138dd... 100% ▕█████████████████████ 148 B                         
pulling 0cb05c6e4e02... 100% ▕█████████████████████ 487 B                         
verifying sha256 digest 
writing manifest 
success 
>>> 请详细介绍你的来历
<think>
您好！我是由中国的深度求索（DeepSeek）公司开发的智能助手DeepSeek-R1。如您有任何任何问题，我会尽我所能为您提供帮助。
</think>

您好！我是由中国的深度求索（DeepSeek）公司开发的智能助手DeepSeek-R1。如您有任何任何问题，我会尽我所能为您提供帮助。

Use Ctrl + d or /bye to exit.

```

后续将介绍如何基于本地模型搭建自己的知识库。
