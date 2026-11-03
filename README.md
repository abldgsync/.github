# actions

本仓库存放一个**可复用的 GitHub 组合 Action(composite action)** `sync`,供 `abldgsync` 组织下各工具仓库(如 `golang`、`kubectl`、`k3s` 等)通过 `uses:` 引用,把各官方源二进制/安装包同步发布到对应仓库的 Releases.

> 引用时写 `abldgsync/.github/sync@main`,通过 `with: tool: <工具名>` 选择具体工具.

## 📁 目录结构

```
actions/
└── sync/                          # 唯一的组合 Action 目录
    ├── action.yaml                # 单一入口(接收 tool 等输入参数)
    ├── dosync.sh                  # 统一入口(极薄):加载 common.sh + tools/${TOOL}.sh 后按 CS 调度
    ├── common.sh                  # 共享逻辑: 下载(S2)/校验(S3)/发布(S4)/调度
    └── tools/                     # 各工具差异配置(仅元数据 + s1_parse)
        ├── golang.sh              # Go 编译器/工具链
        ├── helm.sh                # Helm 二进制
        ├── kubectl.sh             # kubectl 客户端/服务端/节点
        ├── k3s.sh                 # K3s 主二进制 + 离线镜像包
        ├── ziglang.sh             # Zig 编译器
        └── docker_desktop.sh      # Docker Desktop 安装包(每日构建)
```

## 🧩 模块一览

| 模块(`tool`) | 同步内容 | 上游来源 | 校验方式 | 校验类型 |
| --- | --- | --- | --- | --- |
| `golang` | Go 编译器/工具链 | <https://go.dev/dl/> | SHA256(`sha256sum -c`) | `sha256` |
| `helm` | Helm 二进制 | <https://get.helm.sh/> | 在线比对 `.sha256` 文件 | `online` |
| `kubectl` | kubectl 客户端/服务端/节点 | <https://dl.k8s.io> | SHA512(`sha512sum -c`) | `sha512` |
| `k3s` | K3s 主二进制 + 各架构离线镜像包 | <https://github.com/k3s-io/k3s/releases> | SHA256(`sha256sum -c`) | `sha256` |
| `ziglang` | Zig 编译器各平台归档 | <https://ziglang.org/download> | SHA256(`sha256sum -c`) | `sha256` |
| `docker_desktop` | Docker Desktop 安装包/脚本 | <https://desktop.docker.com> 等 | 无官方哈希(跳过) | `skip` |

## 🔧 脚本组织约定

所有工具共用同一套编排:`dosync.sh` 按 `CS` 环境变量(1~4)调度,具体实现全部在 `common.sh`:

| 调用参数 | 阶段职责(共享实现) |
| --- | --- |
| `CS=1` | `s1_parse()`(各工具自定义)解析版本号,写出 `${VN}-binfiles.txt`(下载 URL)与 `${VN}-manifest.txt`(校验清单),并把版本列表写入 `$RUNNER_TEMP/versions.txt` |
| `CS=2` | 基于 `xargs -P 8` 并发下载到 `dist/${VN}/`(失败自动重试) |
| `CS=3` | 按 `CHECKSUM` 类型分发: `sha256`/`sha512` 用 `sum -c` 本地校验; `online` 联网比对; `skip` 为空操作 |
| `CS=4` | 用 `gh` CLI 逐个版本 `gh release create` 发布(首个标 `--latest`,已存在先删后建) |

各 `tools/<tool>.sh` **只需维护两件事**:

1. 元数据:`NAME` / `URL_BASE` / `CHECKSUM` / `TAG_PREFIX` / `KEEP`;
2. `s1_parse()`:拉取上游、按 `WANT` 选版本、写出 binfiles / manifest 两个文件.

> `docker_desktop` 为每日构建(按日期打标签),无官方哈希,故 `CHECKSUM=skip`,`s1_parse` 直接写出固定下载清单.

## 🚀 如何在工具仓库中引用

在各仓库的 `.github/workflows/dosync.yaml` 中:

```yaml
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Sync Golang
        uses: abldgsync/.github/sync@main
        with:
          tool: golang
          binvern: ''   # 不填则用默认(最新两个稳定版),可手动指定版本号
```

各工具支持的输入参数见 `sync/action.yaml` 的 `inputs:`;工具专属参数(`lastn`/`withsvr`/`baseurl`)仅对对应工具生效,对其他工具无害.

## ⚠️ 推送须知

- 引用的是 `sync/` 这个**目录**(组合 Action),必须**把整个目录连同其中文件一起提交推送**,否则 `action.yaml` 中的 `bash "${{ github.action_path }}/dosync.sh"` 会找不到文件,`tools/` 子目录也无法被 `source`.
- 建议把 `@main` 钉成具体 commit SHA 以获得可复现构建.
- 脚本以 `bash <path>` 方式调用,不依赖文件可执行位(已 `chmod +x` 作为双保险).

## 🤝 新增一个同步模块

1. 在 `sync/tools/` 下新建 `<tool>.sh`,提供元数据(`NAME`/`URL_BASE`/`CHECKSUM`/`TAG_PREFIX`/`KEEP`)与 `s1_parse()`;
2. 在 `sync/action.yaml` 的 `inputs.tool.description`(枚举)中登记工具名;
3. 在各工具仓库工作流中用 `uses: abldgsync/.github/sync@main` + `with: { tool: <tool> }` 引用.

无需再新建目录或重复编排脚本 —— 这是相对旧版(每工具一个目录)的最大改进.
