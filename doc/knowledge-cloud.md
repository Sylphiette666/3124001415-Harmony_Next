# 课程知识问答可选云端模型服务

默认离线模式可以完成课程资料问答和来源验证。`cloud/server.mjs` 是可运行的 Node HTTP 代理，使用 OpenAI 兼容的 `/embeddings` 与 `/chat/completions` 协议。模型名称、地址和密钥由部署者配置，不绑定某一家厂商。

本文对应仓库根工程的课程任务 06，与实验二独立。以下命令从仓库根目录执行，使用 Node.js 22.13+，推荐 Node.js 24。

## 启动

复制 `cloud/.env.example` 为本地 `cloud/.env`，填写服务端配置，然后运行：

```powershell
node --env-file=cloud/.env cloud/server.mjs
```

默认仅监听 `127.0.0.1:8787`。部署到支持持续 HTTP 响应的服务器或云函数，在 HTTPS 网关后运行；网关关闭响应缓冲，并配置访问鉴权、调用配额和允许的用户。示例进程具有输入长度限制、每 IP 每分钟 60 次限制和 60 秒上游超时，不承担正式多用户身份管理。

课程 App 问答页的设置只填 HTTPS 代理根地址，不能填写模型密钥。`MODEL_BASE_URL` 是服务端固定地址，客户端不能指定上游或注入密钥。未配置完整模型参数时服务返回 503；测试不访问真实模型，不产生模型费用。

CFKit 云函数是作业提示中的可选转发方式。本实现使用 HTTP/SSE 代理；没有将普通 CFKit `call()` 的整段响应伪装成真实网络流。若迁移为云函数，需确认部署平台支持 SSE 持续响应；不支持时保留本协议的 HTTP 服务。

## 协议

`POST /embeddings`：`{"texts":["问题或片段"]}`，每批 1—16 段，每段不超过 1000 字符。返回 `{"vectors":[[0.1,0.2]],"model":"模型名称:维度"}`。服务核对索引、维度和有限数值。

`POST /answer`：

```json
{"question":"如何保存资料？","context":[{"number":1,"title":"RDB 事务","text":"文档与片段通过事务同步保存。"}]}
```

响应为 UTF-8 `text/event-stream`，每个事件以空行分隔：

```text
data: {"delta":"通过事务"}

data: {"delta":"同步保存。[1]"}

data: {"done":true}

```

失败事件为 `{"error":"提示文字"}`。客户端必须收到 HTTP 200 和 `done` 才视为完成，不能把中断当成成功。服务验证回答含有效引用编号；该检查只证明编号有效，不等于语义事实校验，仍需查看原文。

客户端采用持续 UTF-8 解码，兼容网络块拆开中文、表情、CRLF 或 SSE 边界。服务端将来源作为 JSON 数据提供，并明确禁止执行资料内的角色或工具指令。

参考协议：[Chat Completions 流式事件](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events)。具体模型可用性与鉴权以所选服务商文档为准。
