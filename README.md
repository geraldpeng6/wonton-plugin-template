# 云吞插件模板

开发流程见[插件开发指南](https://github.com/geraldpeng6/wonton-docs/blob/main/develop.md)。

这是一个能安装的示例插件 `app.example.hello`：使用 nginx 官方镜像显示问候页，经网关的 `sso: proxy` 注入用户名，页面显示“你好，<用户名>”。示例没有应用账号、持久化数据或 MCP 工具。

## 示例文件

| 路径 | 内容 |
| --- | --- |
| `docker-compose.yml` | 示例清单、nginx 服务和三个 `configs` |
| `web/default.conf.template` | nginx 配置，启用 SSI 回显用户名并提供健康检查入口；只放行来自核心地址（`${WONTON_CORE_ADDRESS}`）的请求，其余来源 403 |
| `web/index.html` | 问候页 |
| `web/tokens.css` | 页面主题变量的后备值 |
| `tabs/` | 示例主页的底栏图标 |
| `screenshots/home.png` | 商店详情页的示例截图 |
| `scripts/smoke-probes.sh` | 检查真实页面和网关注入身份的插件探针 |

从模板创建自己的插件后，替换示例清单、网页和素材；具体步骤见[写插件](https://github.com/geraldpeng6/wonton-docs/blob/main/develop.md#写插件)。

## 服务端用 libcurl 访问签发方的应用

PHP 等应用在**服务端**用 libcurl 请求 OIDC 签发方；libcurl 从 7.78 起把 `localhost` 和一切
`*.localhost` 当回环，不查 DNS 和 `/etc/hosts`。签发方是 `http://auth.<基础域名>:<端口>`，基础域名
默认 `wonton.localhost`，这些应用连到的是自己的 `127.0.0.1`，登录起不来。Node、Python、Go、Rust 走
系统解析，`sso: proxy` 的应用也不访问签发方，都不用加。

这样的应用要加下面的服务。只有清单是 `webui.sso: oidc` 的插件用得上：`WONTON_OIDC_ISSUER` 只在 oidc 时注入，
别的写法引用了装不上。`scripts/oidc-relay.sh` 由套件维护，`scripts/dev.sh kit-update` 会更新它：

```yaml
  oidc-relay:
    # socat 是 GPL-2.0，独立容器运行，不受链接限制。
    image: docker.io/alpine/socat:1.8.1.3@sha256:466c8a0383e16463fabdb7df01008292fb78d07da60224a46cb5d3142ce122ed
    network_mode: "service:app"
    environment:
      WONTON_OIDC_ISSUER: ${WONTON_OIDC_ISSUER}
    configs:
      - source: oidc-relay
        target: /oidc-relay.sh
    entrypoint: [sh, -ec, ". /oidc-relay.sh"]
    read_only: true
    healthcheck:
      test: ["CMD", "sh", "/oidc-relay.sh", "check"]
      interval: 30s
      timeout: 5s
    restart: unless-stopped
```

服务名固定是 `oidc-relay`，把 `network_mode` 里的 `app` 换成**访问签发方的**服务名，也就是 `webui.service`：
它自己不能再写 `network_mode`（`none`、`host` 都不行，不能链式共用）。`scripts/check.sh` 要求这项指向
`webui.service`、镜像按摘要固定。`network_mode: service:` 要支持它的核心镜像，旧镜像会说只接受
none 或 host。`healthcheck` 连一下本机端口，不转发时算健康。顶层已有 `configs` 时加在同一段里，没有时加：

```yaml
configs:
  oidc-relay:
    file: scripts/oidc-relay.sh
```

转发服务和一次性初始化服务（如 Nextcloud 的 setup）都写在应用的服务名上：应用本体照常对外，它们共用
应用本体的网络命名空间，初始化服务再加
`depends_on: { oidc-relay: { condition: service_started } }`。所有要访问签发方的容器都在这一个命名空间里，
发现文档、令牌、用户信息和 JWKS 都由这一个转发覆盖。

转发服务在签发方端口的 `127.0.0.1` 和 `[::1]` 上监听，TCP 直转，Host 头原样带给核心，签发方以后换成
https 也不用改。应用自己占着同一个端口时起不来，日志写“应用占用了签发方端口 <端口>”，容器以非零退出。
签发方不在 `.localhost` 下时脚本打印一句就空转，容器不动。

## 更新开发套件

```bash
scripts/dev.sh kit-update
```

在从模板新建的插件仓库中更新套件；本仓库是套件源头，执行时只提示并退出。版本、可选引用和自定义脚本约定见[开发指南](https://github.com/geraldpeng6/wonton-docs/blob/main/develop.md#更新开发套件)。

## 图标

`icon.svg` 是本仓库原创线条图标，按本仓库 MIT 许可证分发，见 [NOTICE](NOTICE)。
