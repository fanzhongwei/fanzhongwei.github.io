---
title: 如何从HuggingFace下载并搭建Rerank模型
date: 2025-05-03
tags:
  - AI
  - RAG
  - Rerank
categories:
  - AI
---

# 如何从HuggingFace下载并搭建Rerank模型

## 什么是Rerank模型
Rerank模型的主要任务是对Embedding模型初步筛选出的候选集进行重新排序，确保最相关的结果排在最前面。它通常基于更复杂的语义分析，评估候选文档和查询之间的深层次匹配关系。在Rerank阶段，模型会分析查询与候选文档之间的上下文、语义关系等信息。它可以使用诸如BERT/GPT等预训练语言模型来捕捉更细腻的语义和句子间的关系，从而对初步候选文档进行更精确的评分与排序。Rerank模型一般比Embedding模型计算更复杂，通常需要更多的计算资源，因此适合处理Embedding模型初步检索后的数据。

- **初步检索（Embedding模型）**：用户输入查询后，Embedding模型首先将查询和文档表示为向量，然后通过向量相似度计算，快速从大规模数据集中筛选出若干个候选文档或候选答案。
- **重新排序（Rerank模型）**：在得到初步候选集后，Rerank模型进一步分析这些候选文档或答案与查询之间的精确匹配程度，并根据复杂的语义关系重新打分，对候选集进行排序。


#### 使用Docker安装
采用Docker部署模型，Docker调用GPU，需先安装nvidia-container-toolkits

从存储库更新包列表与安装NVIDIA Container Toolkit
```
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
```
一键部署BAAI/bge-reranker-large模型。
```
docker run --gpus all -p 18080:80 -v /reranker:/data --pull always ghcr.io/huggingface/text-embeddings-inference:turing-1.5 --model-id BAAI/bge-reranker-large
```

#### 直接安装

docker镜像源下载比较慢，这里采用python本地安装

1. 确保系统已安装 Python 3.8 或更高版本，并安装 pip 包管理工具。

```bash
# 检查 Python 版本
python3 --version

# 更新 pip
python3 -m pip install --upgrade pip
```
2. 安装依赖库
BAAI/bge-reranker-large 是一个基于 Transformer 的模型，通常使用 transformers 库加载和运行。安装以下依赖：

```bash
pip install torch transformers
```
- torch: PyTorch 是运行模型的基础框架。
- transformers: Hugging Face 提供的库，用于加载和运行预训练模型。



3. 下载模型

参考文档：[https://huggingface.co/docs/transformers/v4.48.2/zh/installation#离线模式](https://huggingface.co/docs/transformers/v4.48.2/zh/installation#%E7%A6%BB%E7%BA%BF%E6%A8%A1%E5%BC%8F)

```python
from transformers import AutoTokenizer, AutoModelForSequenceClassification

tokenizer = AutoTokenizer.from_pretrained("BAAI/bge-reranker-large")
model = AutoModelForSequenceClassification.from_pretrained("BAAI/bge-reranker-large")

tokenizer.save_pretrained("/home/develop/ai-llm/bge-reranker-large/bge-reranker-large")
model.save_pretrained("/home/develop/ai-llm/bge-reranker-large/bge-reranker-large")


```


4. 提供API服务

如果你不想微调模型，你可以直接安装包，不用finetune依赖：
```
pip install -U FlagEmbedding
```
如果你想微调模型，你可以用finetune依赖安装：
```
pip install -U FlagEmbedding[finetune]
```
使用 FastAPI 部署为服务：`pip install fastapi uvicorn pydantic`

vi bge-reranker-large.py

```
from fastapi import FastAPI
from transformers import AutoModelForSequenceClassification, AutoTokenizer
import torch

app = FastAPI()

# 加载下载好的离线模型和分词器
model_name = "/your/path/bge-reranker-large"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForSequenceClassification.from_pretrained(model_name)
# 如果有GPU
model = model.to("cuda")

# 将模型设置为评估模式
model.eval()

@app.post("/rerank")
def rerank(query: str, document: str):
    inputs = tokenizer(query, document, return_tensors="pt", truncation=True, padding=True)
    with torch.no_grad():
        # 如果有GPU
        inputs = {k: v.to("cuda") for k, v in inputs.items()}
        outputs = model(**inputs)
        score = outputs.logits.item()
    return {"score": score}

```
启动服务：`uvicorn bge-reranker-large:app --reload --host 0.0.0.0 --port 5000`


> 参考文档：https://github.com/FlagOpen/FlagEmbedding/tree/master/examples/inference/reranker#using-huggingface-transformers


访问API进行测试：
```
curl -X POST "http://127.0.0.1:5000/rerank" -H "Content-Type: application/json" -d '{"query": "What is the capital of France?", "document": "Paris is the capital of France."}'
```


产考文档：
- [https://huggingface.co/docs/transformers/v4.48.2/zh/installation#离线模式](https://huggingface.co/docs/transformers/v4.48.2/zh/installation#%E7%A6%BB%E7%BA%BF%E6%A8%A1%E5%BC%8F)
- [https://github.com/FlagOpen/FlagEmbedding/tree/master/examples/inference/reranker#using-huggingface-transformers](https://github.com/FlagOpen/FlagEmbedding/tree/master/examples/inference/reranker#using-huggingface-transformers)
