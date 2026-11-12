# 冒烟约定

`scripts/dev.sh smoke` 是插件合并前的端到端冒烟。作者在自己机器上跑的和合并前的正式冒烟是同一条命令：
正式冒烟取 PR 头部的插件仓库，把开发套件换成本仓库 `main` 的版本，再执行 `scripts/dev.sh smoke`，
只另外负责挑机器、排队和收结果，不为单个插件写额外的钩子。本机先跑 `scripts/dev.sh kit-update`，
结果就和正式冒烟一致。

插件这边只提供两样东西：

- 清单（`docker-compose.yml` 的 `x-wonton`）：有没有 `webui` 决定网页和身份两项跑不跑，`webui.sso` 写进结果说明，
  有没有 `mcp` 决定工具项跑不跑，`permissions` 里有 `models` 时先等模型网关就绪。
- `scripts/smoke-probes.sh`：每一项的探针，写法见文件里的注释。六项之外还要验的（发一条通知、经网关真调一次模型等）
  写成 `extra_check`，结果另记一行“附加检查”。

## 输入

命令行参数都是可选的：

| 参数 | 作用 |
| --- | --- |
| `--upgrade-from <tag>` | 升级保数据从哪个 tag 升上来。不给时取 `git describe` 到的最近 tag；没有 tag 时这一项记 N/A。正式冒烟传插件仓库 `main` 上最新的正式版 tag（`v*`，不含预发布版） |
| `--no-upgrade <原因>` | 不测升级，升级保数据记 N/A 并写上原因，重装保数据照测。给跑冒烟的机器装不到旧版镜像这类调用方的限制用；插件自己的问题不用它掩盖。不能和 `--upgrade-from` 同时给 |
| `--bridge-image <镜像>` | 把清单里 `bridge` 服务的镜像换成这个再装，测未发布的桥。只换工作区这一版，升级起点的 tag 用它自己的清单。清单没有 `bridge` 服务时退出码 2 |

| 环境变量 | 作用 | 不设时 |
| --- | --- | --- |
| `WONTON_PLUGIN` | 一个仓库放多家插件时，插件包目录（相对仓库根，如 `agents/<名>`）。探针放在这个目录的 `smoke-probes.sh`，升级起点只认 `<目录名>/v*` 的 tag | 仓库根就是插件包，探针在 `scripts/smoke-probes.sh` |
| `WONTON_CORE_IMAGE` | 核心镜像 | `ghcr.io/wontonapp/wonton-core:main` |
| `WONTON_PULL` | `never`：用本机已有的核心镜像，不拉取 | 每次起栈先拉取 |
| `WONTON_DEV_CORE_SUBNET` | 核心网络用的子网（如 `192.0.2.0/24`），几套栈共用一台 Docker 时不占默认地址池 | Docker 分配 |
| `WONTON_DEV_EGRESS_PROXY` | 装插件之前先把它配成核心的出口代理 | 不配出口代理 |
| `WONTON_DEV_MODEL_BASE_URL`、`WONTON_DEV_MODEL`、`WONTON_DEV_MODEL_KEY_FILE` | 插件申请了 `models` 时，把这个 OpenAI 兼容的上游接进冒烟实例的模型网关（同 `dev.sh model`）；给了地址就三个都要给，key 只从文件读 | 网关里没有模型 |
| `WONTON_SMOKE_TUNNEL_CLIENT_IMAGE`、`WONTON_SMOKE_ECHO_BOT_IMAGE` | Agent 插件扮演用户手机的两个验收工具（核心仓库 `deploy/dev/core/Dockerfile` 的 `tunnel-client`、`echo-bot` 构建目标）；要手机的附加检查子项用它们 | 这些子项记 N/A 并写原因 |
| `WONTON_SMOKE_CURL_IMAGE` | 经手机的隧道代理取 Matrix 登录令牌用的 curl 镜像 | `curlimages/curl:8.23.0` |
| `WONTON_OWNER_EMAIL` | 用户邮箱 | `owner@wonton.internal`（核心内部邮件收得到的地址） |
| `WONTON_SMOKE_TMPDIR` | 一次性工作区和实例数据放在哪；路径越短越好，宿主网络插件的 unix 套接字路径上限是 107 字节 | `/tmp` |
| `WONTON_SMOKE_MAX_STACKS`、`WONTON_SMOKE_WAIT_MINUTES` | 这台 Docker 上别人的验证栈达到这个数时排队，最多等多少分钟 | 不排队 |
| `SMOKE_WEB_MAX_TIME`、`SMOKE_API_MAX_TIME` | 网页、核心接口请求的超时秒数 | 120、600 |

冒烟只访问本机网关和栈内地址，会在 `no_proxy`、`NO_PROXY` 后面补上 `localhost`、`127.0.0.1`、`.localhost`、
`wonton.internal` 这些地址，主机导出的上网代理不会截走这些请求。探针里自己写的 `curl` 也建议带 `--noproxy '*'`。

## 探针能用的变量和助手

探针在冒烟开始时就被读入，下面的变量要到对应的项开始前才有值：只在函数里读，不要在文件顶层读。

| 变量 | 内容 |
| --- | --- |
| `SMOKE_WEB_URL` | 应用的网页入口，即核心插件列表里的 `web_url` 去掉结尾的 `/`；清单写了 `webui.path` 时带着这个路径 |
| `SMOKE_WEB_ORIGIN` | 只有 `scheme://host:port`；拼应用自己的 API 路径用它，不要接在 `SMOKE_WEB_URL` 后面 |
| `SMOKE_BASE`、`SMOKE_TOKEN` | 核心的地址和用户令牌 |
| `SMOKE_OWNER`、`SMOKE_OWNER_EMAIL` | 用户名和邮箱 |
| `SMOKE_PLUGIN_ID`、`SMOKE_SLUG` | 插件 id，和把 `.` 换成 `-` 的写法（容器名、MCP 工具前缀用它） |
| `SMOKE_WEBUI`、`SMOKE_SSO`、`SMOKE_MCP` | 从清单读出的：有没有网页（1/0）、`webui.sso`、有没有 MCP（1/0） |
| `SMOKE_INSTANCE`、`SMOKE_CORE`、`SMOKE_DATA_DIR` | 实例名、核心容器名、核心容器里的数据目录 |
| `SMOKE_STATE` | 数据标记文件：`data_write` 覆盖写，`data_check` 读 |
| `SMOKE_JAR` | 用户会话的 cookie 文件 |
| `SMOKE_DIR` | 这次冒烟复制出来的工作区 |
| `SMOKE_TOOLS`、`SMOKE_MCP_URL` | 工具项里 `tools/list` 的结果文件和 MCP 总线地址 |

| 助手 | 用法 |
| --- | --- |
| `web_get <路径> [curl 参数…]` | 带用户会话请求 `SMOKE_WEB_URL` 后接这个路径 |
| `dweb [--sso] [<路径> [curl 参数…]]` | 即 `scripts/dev.sh web`：先走登录跳转（`--sso` 还会提交应用登录页的自动表单），路径接在 `SMOKE_WEB_ORIGIN` 后 |
| `smoke_api <方法> <路径> [curl 参数…]` | 带用户令牌调核心管理接口 |
| `mcp list`、`mcp call <工具> [<JSON>]` | 经 MCP 总线列出、调用工具 |
| `probes_owner_room_wait <秒> <文字>` | 等用户的通知房间里出现包含这段文字的新消息 |
| `extra_item <PASS\|FAIL\|N/A> <子项> <说明>` | 只在 `extra_check` 里用：记一行附加检查的子项 |
| `agent_check_*`、`agent_say` | Agent 插件的附加检查（加密私聊、模型回答、MCP 工具、确认卡片、打断、重启、续聊、名单外不应答），用法见 `scripts/agent-probes.sh` 开头 |

`extra_check` 默认限时 600 秒，探针里写 `EXTRA_TIMEOUT=<秒>` 可以放宽（Agent 插件一轮要发十几条消息）。

登录跳转和网页请求带的是浏览器同款的 `Accept`（含 `*/*`），按内容协商的登录入口不会回 406。

## 输出

标准输出是进度行（`== ` 开头）和结果行。结果行的格式：

```text
PASS <项>：<说明>
FAIL <项>：<说明>
N/A  <项>：<说明>
```

标签和项名之间是空白，项名和说明之间是全角冒号。项名固定为六个：`装得上`、`网页打得开`、`用户身份能用`、
`工具Bot调得到`、`升级保数据`、`重装保数据`；同一项可能有不止一行，有一行 FAIL 就算这项失败。探针写了 `extra_check`
时另有一行 `附加检查`，FAIL 同样算失败。`extra_check` 用 `extra_item` 记了子项时，先逐行打印子项
`PASS 附加检查·<子项>：<说明>`（同一子项可以有几行），再打汇总的 `附加检查`：钩子返回非 0 或任一子项 FAIL 时是 FAIL，
子项全是 N/A 时是 N/A，否则 PASS。跑完清理后还有残留时另有一行 `FAIL 清理：…`。

详细日志写在工作区的 `.wonton/smoke.log`，结果行里的“看日志”指的就是它。

## 退出码

| 退出码 | 含义 |
| --- | --- |
| 0 | 没有 FAIL（N/A 不算失败） |
| 1 | 有 FAIL；或者冒烟没跑完（缺工具、同一仓库已有一套冒烟在跑、清单解析不了等），这时标准错误有原因、没有六项的结果行 |
| 2 | 参数写错了，或 `--bridge-image` 用在没有 `bridge` 服务的插件上 |
