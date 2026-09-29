# abldgsync

> 自动把各类官方二进制 / 安装包同步到本组织各仓库的 GitHub Releases,便于网络受限环境下稳定获取.

本组织通过 GitHub Actions 周期性(或手动)从各上游官方源拉取软件发行物,完成**校验**后发布到对应仓库的 Releases,形成一份可信,可控的二进制镜像.

<!-- 仓库地址统一管理:修改组织名或仓库名只需改这里 -->
[golang]: https://github.com/abldgsync/golang "abldgsync/golang 仓库"
[kubectl]: https://github.com/abldgsync/kubectl "abldgsync/kubectl 仓库"
[helm]: https://github.com/abldgsync/helm "abldgsync/helm 仓库"
[k3s]: https://github.com/abldgsync/k3s "abldgsync/k3s 仓库"
[ziglang]: https://github.com/abldgsync/ziglang "abldgsync/ziglang 仓库"
[docker_desktop]: https://github.com/abldgsync/docker_desktop "abldgsync/docker_desktop 仓库"
[shared_actions]: https://github.com/abldgsync/shared_actions "abldgsync/shared_actions 仓库"

## 📦 仓库总览

| 仓库 | 同步内容 | 上游来源 |
| --- | --- | --- |
| [golang][golang] | Go 编译器 / 工具链(各平台归档,安装包,源码) | <https://go.dev/dl/> |
| [kubectl][kubectl] | Kubernetes `kubectl` 客户端 / 服务端 / 节点二进制 | <https://dl.k8s.io> |
| [helm][helm] | Helm 命令行二进制 | <https://get.helm.sh/> |
| [k3s][k3s] | K3s 主二进制及各架构离线镜像包 | <https://github.com/k3s-io/k3s/releases> |
| [ziglang][ziglang] | Zig 编译器各平台归档与源码 | <https://ziglang.org/download> |
| [docker_desktop][docker_desktop] | Docker Desktop 各平台安装包 / 安装脚本(按日构建) | <https://desktop.docker.com> 等 |

## 🏗️ 架构

- **共享 Action 仓库 [shared_actions][shared_actions]**:每个工具对应一个组合 Action `sync_<tool>/`,被各工具仓库的工作流以 `uses: abldgsync/shared_actions/sync_<tool>@main` 引用(建议将 `@main` 钉定为具体 commit SHA 以获得可复现构建).
- **工作流模板统一**:每个工具仓库的 `.github/workflows/dosync.yaml` 结构一致,仅一行 `uses` 指向对应的共享 Action,便于维护.
- **脚本化阶段**:每个 `sync_<tool>/scripts/` 下按职责拆分为带序号的脚本,逻辑清晰,可单独调试:
  - `s1_resolve.sh` ---- 解析版本并生成下载 / 校验清单
  - `s2_download.sh` ---- 基于 `xargs -P 8` 并发下载(失败自动重试)
  - `s3_verify.sh` ---- 用官方校验和(`sha256sum` / `sha512sum -c`)逐文件校验
  - `s4_publish.sh` ----(仅 k3s)用 `gh` CLI 发布到 Releases;其余工具由 `softprops/action-gh-release` 完成发布

## ⚙️ 通用流程

```
解析版本 → 组装下载清单 → 并行下载 → 校验完整性(官方 checksum) → 发布到 Releases
```

- **版本解析**:默认取最新稳定版;支持手动指定版本号或系列前缀(如 kubectl/k3s 的 `v1.31`,golang 的 `go1.23`,helm 的 `v3.15`,zig 的 `0.13`).
- **预发布过滤**:`rc` / `beta` / `alpha` / `-dev` 等非稳定版本会被跳过或报错,避免误发.
- **校验优先**:所有文件下载后均对照上游官方校验和文件核验,确保完整性.

## 🔁 触发方式

- **手动触发(`workflow_dispatch`)**:在仓库 Actions 页面手动运行,可传入版本号等参数.
- **定时触发(`schedule`)**:各仓库按需在 `dosync.yaml` 中配置(如 golang 每周,docker_desktop 每日;k3s 预留按月,zig 默认关闭),取消注释即可启用.

## 🔐 校验与安全

- 全部产物来自各项目**官方 Release / 官网**,并经过官方提供的哈希校验.
- 调用 GitHub API 时携带 `GITHUB_TOKEN`,既提升限流也保证来源可信.

## 🤝 参与方式

- 新增工具:在 `shared_actions` 增加 `sync_<tool>/`,参照既有模块提供 `s1~s3` 脚本(k3s 另含 `s4_publish.sh`),再于对应仓库建立 `dosync.yaml` 引用即可.
- 反馈与贡献:欢迎通过 Issue / PR 提交建议与改进.

## 📄 许可

本组织仓库采用 MIT License(详见各仓库 `LICENSE`).
