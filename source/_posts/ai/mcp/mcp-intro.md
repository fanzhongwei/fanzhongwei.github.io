---
title: MCP简介及其工作原理
date: 2025-05-14
tags:
  - AI
  - MCP
categories:
  - AI
---

> 摘要：Anthropic推出的模型上下文协议（MCP）通过标准化接口实现大语言模型与内外部工具的安全互联。本文详解MCP工作原理，揭示Prompt工程如何成为工具调用的关键枢纽，为AI应用生态提供"即插即用"式扩展能力。

# 模型上下文协议（Model Context Protocol，MCP）

模型上下文协议（Model Context Protocol，MCP），是由 Anthropic推出的开源协议，旨在实现大语言模型与外部数据源和工具的集成，用来在大模型和数据源之间建立安全双向的连接。

MCP 是一个开放协议，它标准化了应用程序向 LLM 提供上下文的方式。可以将 MCP 视为AI应用的 USB-C 端口。正如USB-C提供了一种标准化的方式将您的设备连接到各种外围设备和配件一样，MCP提供了一种标准化的方式将 AI 模型连接到不同的数据源和工具。

## MCP架构

MCP遵循客户端 - 服务器架构，包含以下几个核心部分：
- MCP 主机（MCP Hosts）：发起请求的 AI 应用程序，比如聊天机器人、AI 驱动的 IDE 等。
- MCP 客户端（MCP Clients）：在主机程序内部，与 MCP 服务器保持 1:1 的连接。
- MCP 服务器（MCP Servers）：为 MCP 客户端提供上下文、工具和提示信息。
- 本地资源（Local Resources）：本地计算机中可供 MCP 服务器安全访问的资源，如文件、数据库。
- 远程资源（Remote Resources）：MCP 服务器可以连接到的远程资源，如通过 API 提供的数据。

![MCP架构](https://mmbiz.qpic.cn/mmbiz_jpg/Z6bicxIx5naI1MWDBvOvKpP7WAY0ebsGatkrs3bVbq5L6fJtc84ttRIqibekVSZ4qQSqkMHIu939qvZWcCmmh9eA/640?wx_fmt=other&from=appmsg&tp=wxpic&wxfrom=5&wx_lazy=1)


## 大模型如何识别并调用MCP

LLM（模型）是在什么时候确定使用哪些工具的呢？Anthropic为我们提供了详细的解释，当用户提出一个问题时：

- 客户端（Claude Desktop / Cursor）将问题发送给 LLM。
- LLM 分析可用的工具，并决定使用哪一个（或多个），实际上**模型是依靠prompt来识别当前可用的工具有哪些**。
- 客户端通过 MCP Server 执行所选的工具。
- 工具的执行结果被送回给 LLM。LLM 结合执行结果，归纳总结后生成自然语言展示给用户！

![MCP工作原理](https://mmbiz.qpic.cn/mmbiz_jpg/Z6bicxIx5naI1MWDBvOvKpP7WAY0ebsGaNticc7Noo7wAiaHZCo4AHJeJxdSs5J9hv7D2giaI3UPft6JnYWiaqSeWQg/640?wx_fmt=other&from=appmsg&tp=wxpic&wxfrom=5&wx_lazy=1)


我们可以参考MCP官方提供的[python-sdk client example](https://github.com/modelcontextprotocol/python-sdk/blob/main/examples/clients/simple-chatbot/mcp_simple_chatbot/main.py)为讲解示例

```python
    async def start(self) -> None:
        """Main chat session handler."""
        try:
            # 初始化所有的 mcp server
            for server in self.servers:
                try:
                    await server.initialize()
                except Exception as e:
                    logging.error(f"Failed to initialize server: {e}")
                    await self.cleanup_servers()
                    return

            # 获取所有的 tools 命名为 all_tools
            all_tools = []
            for server in self.servers:
                tools = await server.list_tools()
                all_tools.extend(tools)

            # 将所有的 tools 的功能描述格式化成字符串供 LLM 使用
            tools_description = "\n".join([tool.format_for_llm() for tool in all_tools])

            # 询问 LLM（Claude） 应该使用哪些工具。
            system_message = (
                "You are a helpful assistant with access to these tools:\n\n"
                f"{tools_description}\n"
                "Choose the appropriate tool based on the user's question. "
                "If no tool is needed, reply directly.\n\n"
                "IMPORTANT: When you need to use a tool, you must ONLY respond with "
                "the exact JSON object format below, nothing else:\n"
                "{\n"
                '    "tool": "tool-name",\n'
                '    "arguments": {\n'
                '        "argument-name": "value"\n'
                "    }\n"
                "}\n\n"
                "After receiving a tool's response:\n"
                "1. Transform the raw data into a natural, conversational response\n"
                "2. Keep responses concise but informative\n"
                "3. Focus on the most relevant information\n"
                "4. Use appropriate context from the user's question\n"
                "5. Avoid simply repeating the raw data\n\n"
                "Please use only the tools that are explicitly defined above."
            )

            messages = [{"role": "system", "content": system_message}]

            while True:
                try:
                    user_input = input("You: ").strip().lower()
                    if user_input in ["quit", "exit"]:
                        logging.info("\nExiting...")
                        break

                    messages.append({"role": "user", "content": user_input})

                    # 将 system_message 和用户消息输入一起发送给 LLM
                    llm_response = self.llm_client.get_response(messages)
                    logging.info("\nAssistant: %s", llm_response)

                    # 处理 LLM 的输出（如果有 tool call 则执行对应的工具）
                    result = await self.process_llm_response(llm_response)

                    # 如果 result 与 llm_response 不同，说明执行了 tool call （有额外信息了）
                    # 则将 tool call 的结果重新发送给 LLM 进行处理。
                    if result != llm_response:
                        messages.append({"role": "assistant", "content": llm_response})
                        messages.append({"role": "system", "content": result})

                        final_response = self.llm_client.get_response(messages)
                        logging.info("\nFinal response: %s", final_response)
                        messages.append(
                            {"role": "assistant", "content": final_response}
                        )
                    # 否则代表没有执行 tool call，则直接将 LLM 的输出返回给用户。
                    else:
                        messages.append({"role": "assistant", "content": llm_response})

                except KeyboardInterrupt:
                    logging.info("\nExiting...")
                    break

        finally:
            await self.cleanup_servers()
```

根据上面的源码分析，可以看出**工具文档至关重要**。模型依赖于工具描述文本来理解和选择适用的工具，这意味着精心编写的工具名称、文档字符串（docstring）以及参数说明显得尤为重要。鉴于MCP的选择机制基于prompt实现，理论上任何模型只要能够提供相应的工具描述就能与MCP兼容使用。


参考文档：
- https://modelcontextprotocol.io/introduction
- https://github.com/modelcontextprotocol/python-sdk/blob/main/examples/clients/simple-chatbot/mcp_simple_chatbot/main.py