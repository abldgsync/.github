# abldgsync

> 自动把各类官方二进制 / 安装包同步到本组织各仓库的 GitHub Releases，便于网络受限环境下稳定获取。

本组织通过 GitHub Actions 周期性（或手动）从各上游官方源拉取软件发行物，完成**校验**后发布到对应仓库的 Releases，形成一份可信、可控的二进制镜像。

<!-- 仓库地址统一管理：修改组织名或仓库名只需改这里 -->
[golang]: https://github.com/abldgsync/golang "abldgsync/golang 仓库"
[kubectl]: https://github.com/abldgsync/kubectl "abldgsync/kubectl 仓库"
[helm]: https://github.com/abldgsync/helm "abldgsync/helm 仓库"
[k3s]: https://github.com/abldgsync/k3s "abldgsync/k3s 仓库"
[ziglang]: https://github.com/abldgsync/ziglang "abldgsync/ziglang 仓库"
[docker_desktop]: https://github.com/abldgsync/docker_desktop "abldgsync/docker_desktop 仓库"

## 📦 仓库总览

| 仓库 | 同步内容 | 上游来源 | 校验方式 |
| --- | --- | --- | --- |
| [golang][golang] | Go 编译器 / 工具链（各平台归档、安装包、源码） | <https://go.dev/dl/> | SHA256 |
| [kubectl][kubectl] | Kubernetes `kubectl` 客户端 / 服务端 / 节点二进制 | <https://dl.k8s.io> | SHA512 |
| [helm][helm] | Helm 命令行二进制 | <https://get.helm.sh/> | 在线比对 `.sha256` |
| [k3s][k3s] | K3s 主二进制及各架构离线镜像包 | <https://github.com/k3s-io/k3s/releases> | SHA256 |
| [ziglang][ziglang] | Zig 编译器各平台归档与源码 | <https://ziglang.org/download> | SHA256 |
| [docker_desktop][docker_desktop] | Docker Desktop 各平台安装包 / 安装脚本（按日构建） | <https://desktop.docker.com> 等 | 无官方哈希（跳过） |

## 🏗️ 架构

- **共享组合 Action `abldgsync/.github/sync`**：所有工具的同步逻辑收敛为**单一组合 Action**，被各工具仓库的工作流以 `uses: abldgsync/.github/sync@main` 引用，并通过 `with: tool: <工具名>` 选择具体工具。
- **共享编排，工具只差异化**：`sync/dosync.sh` 承载统一的阶段调度与下载 / 校验 / 发布实现；每个工具仅在 `sync/tools/<tool>.sh` 中维护**元数据**（`NAME` / `URL_BASE` / `CHECKSUM` / `TAG_PREFIX` / `KEEP`）与 `s1_parse()`（拉取上游、选版本、生成下载 / 校验清单）。新增工具无需重复编排脚本。

  | 文件 | 职责 |
  | --- | --- |
  | `sync/action.yaml` | 单一入口，接收 `tool` / `binvern` / `lastn` / `withsvr` 等输入参数 |
  | `sync/dosync.sh` | 极薄入口：加载 `tools/${TOOL}.sh` 后按 `CS` 调度；共享的下载 / 校验 / 发布逻辑也内联于此 |
  | `sync/tools/<tool>.sh` | 仅元数据 + `s1_parse()`，工具间唯一差异所在 |

- **脚本化阶段**：`dosync.sh` 按 `CS` 环境变量（1~4）调度：

  | 调用参数 | 阶段职责 |
  | --- | --- |
  | `CS=1` | `s1_parse()`（各工具自定义）解析版本号，写出 `${VN}-binfiles.txt`（下载 URL）与 `${VN}-manifest.txt`（校验清单），并把版本列表写入 `$RUNNER_TEMP/versions.txt` |
  | `CS=2` | 基于 `xargs -P 8` 并发下载到 `dist/${VN}/`（失败自动重试） |
  | `CS=3` | 按 `CHECKSUM` 类型分发：`sha256` / `sha512` 用 `sum -c` 本地校验；`online` 联网比对；`skip` 为空操作 |
  | `CS=4` | 用 `gh` CLI 逐个版本 `gh release create` 发布（首个标 `--latest`，已存在先删后建） |

> 引用的是 `sync/` 这个**目录**（组合 Action），必须连同其中文件一起提交推送，否则 `action.yaml` 中的 `bash "${{ github.action_path }}/dosync.sh"` 会找不到文件，`tools/` 子目录也无法被 `source`。建议把 `@main` 钉成具体 commit SHA 以获得可复现构建。

## ⚙️ 通用流程

```
解析版本 → 组装下载清单 → 并行下载 → 校验完整性（官方 checksum） → 发布到 Releases
```

- **版本解析**：默认取最新稳定版；支持手动指定版本号或系列前缀（如 kubectl / k3s 的 `v1.31`、golang 的 `go1.23`、helm 的 `v3.15`、zig 的 `0.13`）。
- **预发布过滤**：`rc` / `beta` / `alpha` / `-dev` 等非稳定版本会被跳过或报错，避免误发。
- **校验优先**：所有文件下载后均对照上游官方校验和核验，确保完整性。

## 🚀 如何在工具仓库中引用

在各仓库的 `.github/workflows/dosync.yaml` 中：

```yaml
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Sync <Tool>
        uses: abldgsync/.github/sync@main
        with:
          tool: <tool>        # golang / helm / kubectl / k3s / ziglang / docker_desktop
          binvern: ''         # 不填则用默认（最新稳定版），可手动指定版本号
```

各工具支持的输入参数见 `sync/action.yaml` 的 `inputs:`；工具专属参数（`lastn` / `withsvr`）仅对对应工具生效，对其他工具无害。

## 🔁 触发方式

- **手动触发（`workflow_dispatch`）**：在仓库 Actions 页面手动运行，可传入版本号等参数。
- **定时触发（`schedule`）**：各仓库按需在 `dosync.yaml` 中配置（如 golang 每月、docker_desktop 每日；k3s 预留按月、zig 默认关闭），取消注释即可启用。

## 🤝 新增一个同步模块

1. 在 `sync/tools/` 下新建 `<tool>.sh`，提供元数据（`NAME` / `URL_BASE` / `CHECKSUM` / `TAG_PREFIX` / `KEEP`）与 `s1_parse()`；
2. 在 `sync/action.yaml` 的 `inputs.tool.description`（枚举）中登记工具名；
3. 在各工具仓库工作流中用 `uses: abldgsync/.github/sync@main` + `with: { tool: <tool> }` 引用。

无需再新建目录或重复编排脚本。

## 🔐 校验与安全

- 全部产物来自各项目**官方 Release / 官网**，并经过官方提供的哈希校验。
- 调用 GitHub API 时携带 `GITHUB_TOKEN`，既提升限流也保证来源可信。

## 📄 许可

- 各**二进制镜像仓库**（golang / helm / kubectl / k3s / ziglang / docker_desktop）为上游官方发行物的镜像，本身不附带独立 LICENSE 文件；所含二进制的许可随各自上游项目（Go / Kubernetes / Helm / K3s / Zig / Docker 等）而定，请以对应上游的许可证为准。
- 本组织基础设施仓库 `abldgsync/.github` 采用 MIT License。
