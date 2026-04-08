---
title: 基于Dify + DeepSeek部署本地知识库
date: 2025-05-10
tags:
  - AI
  - RAG
  - Dify
categories:
  - AI
---

# 基于Dify + DeepSeek部署本地知识库

本地部署的最大意义在于利用DeepSeek大模型的能力加上自己的知识库，可以训练出一个符合自己需求的大模型。

今天就来分享下这个搭建过程，使用基于LLM的大模型知识库问答系统Dify，里面集成DeepSeek以及私有知识库，打造一个符合自己需求的RAG应用。


## 1、安装Docker

安装Docker和Docker-compose，windows系统可以在docker网站 https://www.docker.com/ 下载docker desktop。

这里以linux为例，安装docker。

### docker安装请参照官网教程
  
```shell
# docker
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
sudo service docker restart
sudo systemctl enable docker

```

### Docker Compose
```shell
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
docker-compose version
```

### 设置docker镜像源
```shell
vi /etc/docker/daemon.json
{"registry-mirrors":[
        "https://registry.docker-cn.com",
        "https://hub-mirror.c.163.com/"

]}
```

最后重启doker
systemctl restart docker


## 2、安装Dify

Dify文档参见：[https://github.com/langgenius/dify](https://github.com/langgenius/dify)

1. clone dify源码：`https://github.com/langgenius/dify.git`
2. 构建docker镜像，启动docker容器
```shell
cd dify
cd docker
cp .env.example .env
docker compose up -d
```
3. 浏览器访问：[http://localhost/install](http://localhost/install)，进行初始化

## 3、配置模型

### 配置LLM模型

之前的文章我们已经介绍了，如何本地部署DeepSeek：[https://note.youdao.com/s/mJWh4ya](https://note.youdao.com/s/mJWh4ya)，接下来就以本地部署的DeepSeek为例添加到Dify中。

1. 进入Dify页面，点击右上角头像-》设置，进入设置页面
2. 选择模型供应商，找到Ollama
3. 添加Ollama模型，如下图所示
![DeepSeek模型配置.png](https://mmbiz.qpic.cn/mmbiz_png/14Blum0GwI7zfMWdeXcoUMs1Rv8Qc6atpQQuYgN3MrxnWjaCQfb2CwgLll5oHAsnhagSDfzTpnh7lSEsUvBcDg/640?wx_fmt=png&amp;from=appmsg)
    - 模型类型：LLM
    - 模型名称：下载的模型名称，例如：deepseek-r1:8b
    - 基础URL：Ollama部署的地址，默认端口为11434


### 配置Text Embedding模型

Text Embedding（文本嵌入）模型的核心作用是将文本（单词、句子、段落或文档）转换为稠密向量（即一组数值构成的向量），从而让计算机能够量化、理解和处理文本的语义信息。

Dify将使用Text Embedding模型将用户输入的问题转换为向量，到知识库根据语义快速检索知识。

Text Embedding模型如何选择，以下是主流Text Embedding模型的对比表格，从多个维度对比其优劣，帮助根据场景选择合适模型：

| 模型名称          | 参数量 | 上下文长度 | 多语言支持 | 特色优势                          | 主要缺点                          | 适用场景                          |
|-------------------|--------|------------|------------|-----------------------------------|-----------------------------------|-----------------------------------|
| **OpenAI text-embedding-3** | 未知   | 8192       | 是         | 高准确度，OpenAI生态兼容          | 收费API，隐私数据需谨慎           | 商业应用，预算充足的项目          |
| **BAAI/bge-large** | 1.1B   | 512        | 是(侧重中英)| 中文任务领先，开源可商用          | 长文本需分段处理                  | 中文搜索、问答系统                |
| **Alibaba-NLP/gte-large** | 0.6B   | 512        | 是         | 阿里巴巴优化，文档理解强          | 资源消耗较大                      | 电商、长文档处理                  |
| **Google/Gecko**  | 0.3B   | 1024       | 是         | 轻量高效，谷歌搜索优化            | 精度略低于大模型                  | 移动端、实时检索系统              |
| **sentence-transformers/all-MiniLM** | 22M    | 256        | 是         | 超轻量级，推理速度快              | 表达能力有限                      | 边缘设备、低延迟场景              |
| **Cohere/embed-multilingual** | 0.3B   | 512        | 是(100+语言)| 多语言均衡表现                    | 英文略逊于专用模型                | 跨国多语言应用                    |
| **MokaAI/m3e-base** | 0.3B   | 512        | 中文优化    | 中文CL任务专项优化                | 非中文任务较弱                    | 中文语义相似度计算                |


> 注：最新模型建议查看HuggingFace的MTEB排行榜（https://huggingface.co/spaces/mteb/leaderboard ）获取实时评测数据。实际选择时应通过自己的测试集验证。

Dify配置Text Embedding模型步骤如下：
1. 进入Dify页面，点击右上角头像-》设置，进入设置页面
2. 选择模型供应商，找到Ollama
3. 添加Ollama模型，添加：bge-large
    - 模型类型：Text Embedding
    - 模型名称：bge-large
    - 基础URL：Ollama部署的地址，默认端口为11434

### 配置Rerank模型

Rerank模型的主要任务是对Text Embedding模型初步筛选出的候选集通过深度语义理解进行重新排序，确保最相关的结果排在最前面。

Ollama中目前没有找到合适的Rerank模型，这里考虑从**HugginFace中下载BAAI/bge-reranker-large**模型，使用**transformers**搭建一个满足**OpenAI-API-compatible**协议类型的Rerank模型，方便加入到Dify中。

安装BAAI/bge-reranker-large模型请参考：[如何从HuggingFace下载并搭建Rerank模型](https://note.youdao.com/s/4PQbFYtZ)

Dify配Rerank模型步骤如下：
1. 进入Dify页面，点击右上角头像-》设置，进入设置页面
2. 选择模型供应商，找到OpenAI-API-compatible
3. 添加OpenAI-API-compatible模型，添加：bge-reranker-large
    - 模型类型：Rerank
    - 模型名称：bge-reranker-large
    - 基础URL：http://ip:port/v1


## 4、构建知识库

到这里基础的模型已经配置完成，接下来我们开始搭建知识库，进入Dify的知识库页面点击创建知识库，选择文件后进行如下配置：

![Dify创建知识库](https://mmbiz.qpic.cn/mmbiz_png/14Blum0GwI7zfMWdeXcoUMs1Rv8Qc6atJm5p7VDNNdyIG2ulqQ6w317ukv9WruaicXlVYKJWkusicAzKAU5O0Rwg/640?wx_fmt=png&amp;from=appmsg)

然后点击保存并处理，等待索引处理完成，即可使用该知识库。

其中选择的模型在知识库检索过程中有不同的作用：
- Text Embedding模型：
    - 用于召回阶段（Retrieval），从海量文档中快速筛选出Top-K（如1000条）候选结果。
    - 通过向量相似度（如余弦相似度）粗筛，保证高召回率（Recall）。
- Rerank模型：
    - 用于排序阶段（Reranking），对Top-K候选结果精细排序。
    - 通过深度语义理解（如交叉注意力）计算查询-文档对的相关性，提升准确率（Precision）。

> 示例流程：用户查询 → [Embedding模型] → 召回1000条候选 → [Rerank模型] → 返回Top-10最相关结果


## 5、创建聊天应用

进入Dify的工作室，创建空白应用 -》选择Chatflow类型创建应用，进行工作流编排：

![Dify创建应用.png](https://mmbiz.qpic.cn/mmbiz_png/14Blum0GwI7zfMWdeXcoUMs1Rv8Qc6atO0pNtZIiaERLeOQHpaGtvQ2ibOoYIWib9j5SF5iaFPLGgBA1YNt76V0MLA/640?wx_fmt=png&amp;from=appmsg)

> tips：知识库中的知识图片最好是具有语义的markdown格式（例如：\!\[用户登陆.png](https://xxxx)），这样大模型才能更好的以图文方式回答用户的问题。

## 应用调试和发布

点击预览按钮可以对编排的工作流进行调试，其中每一步可点开查看具体输入和输出：
![Dify应用预览.png](https://mmbiz.qpic.cn/mmbiz_png/14Blum0GwI7zfMWdeXcoUMs1Rv8Qc6atIPW7UcM86n0mA6J0WA3nTDCHzpWME2VWDVmWTEibvGpICibYwFjrwzbw/640?wx_fmt=png&amp;from=appmsg)

应用调试完成后，点击发布按钮即可进行发布，发布后点击运行可以打开Dify提供的默认聊天页面。Dify提供的聊天页面支持嵌入到其它网站，同时也提供一系列API接口以供开发者深度集成，大家可根据自己需求自由选择。


参考文档：
- [https://github.com/langgenius/dify](https://github.com/langgenius/dify)
- [https://huggingface.co/spaces/mteb/leaderboard](https://huggingface.co/spaces/mteb/leaderboard)
