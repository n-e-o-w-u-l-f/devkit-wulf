# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

一个安全、由清单驱动的多平台开发环境引导程序与编排器，面向 Windows、WSL2、Linux、macOS、BSD，以及经过明确研究的扩展 Unix 目标系统。

> **状态：** 当前为 1.0 之前阶段。平台/环境组合在通过所需 CI 与目标系统验证门禁之前均保持为 `experimental`。仅存在适配器并不意味着已提升为正式支持。

截至 **2026-08-11** 的审计状态见 [`docs/REPOSITORY-STATUS.md`](docs/REPOSITORY-STATUS.md)。

## 架构

`devkit-wulf` 将主机/体系结构检测、来源与软件包管理器选择、环境契约、无修改计划、完整性验证、运行时验证、状态/所有权以及 CI/发布门禁彼此分离。

共享的版本化契约位于 `environments/`。面向发布的系统原生入口位于 `installers/`。`bin/` 在迁移期间仅保留内部通用编排核心，不是可跨所有操作系统运行的“通用发布格式”。

详见 [`docs/installer-architecture.md`](docs/installer-architecture.md)。

## 快速开始

### 原生 Linux

```sh
./bootstrap/linux.sh
./installers/linux/devkit-wulf.sh detect
./installers/linux/devkit-wulf.sh list
./installers/linux/devkit-wulf.sh plan python
./installers/linux/devkit-wulf.sh install python --experimental
./installers/linux/devkit-wulf.sh verify python
```

### macOS

```sh
./bootstrap/macos.sh
./installers/macos/devkit-wulf.sh detect
./installers/macos/devkit-wulf.sh plan python
```

### Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap\windows.ps1
.\installers\windows\devkit-wulf.ps1 detect
.\installers\windows\devkit-wulf.ps1 list
.\installers\windows\devkit-wulf.ps1 plan python
.\installers\windows\devkit-wulf.ps1 install python -Experimental
.\installers\windows\devkit-wulf.ps1 verify python
```

Windows PowerShell 5.1 与 PowerShell 7 均受入口脚本接受。基于 WinGet 的安装会在修改前检查精确的软件包 ID。

### WSL2

在所选 WSL 发行版内部使用 WSL 入口：

```sh
./bootstrap/linux.sh
./installers/wsl/devkit-wulf.sh detect
./installers/wsl/devkit-wulf.sh plan python
```

`devkit-wulf` 不会静默创建 WSL 发行版，也不会自动把 WSL1 转换为 WSL2。Windows 侧系统修改必须先显式规划，并使用 `-AllowSystemChange`。

## 版本化系统原生选择器

截至 **2026-08-11** 的审计状态：

| 选择器 | Linux | WSL2 | macOS | Windows |
| --- | --- | --- | --- | --- |
| `python@3.12` | 实验性路由 | 实验性路由 | 实验性路由 | 实验性路由 |
| `go@stable` | 实验性路由 | 实验性路由 | 实验性路由 | 实验性路由 |
| `rust@stable` | 实验性路由 | 实验性路由 | 实验性路由 | 已有适配器，中央路由仍封锁 |
| `flutter@stable` | 实验性路由 | unsupported | 实验性路由 | 实验性路由（amd64） |
| `kubectl@stable` | 未中央路由 | 未中央路由 | 已有直接原生适配器 | 已有直接原生适配器 |

此表描述的是实现/路由，**不是已提升的支持状态**。Go 的 Windows 工作流仍包含已过时的 fail-closed 假设（issue #35）。Windows Rust 则相反：原生适配器已经存在，但中央选择器仍有意保持封锁。

## 环境与配置文件

主要环境：

`base`、`cpp`、`python`、`node`、`deno`、`bun`、`java`、`dotnet`、`go`、`rust`、`php`、`ruby`、`vscode`、`visualstudio`、`jetbrains`、`eclipse`、`android`、`flutter`、`xcode`、`docker`、`podman`、`kubectl`、`opentofu`。

配置文件：

`minimal`、`web`、`backend`、`systems`、`mobile`、`devops`、`full`、`wsl-stable`、`wsl-rolling`。

**已知契约漂移：** `profiles/profiles.json` 与 `tests/validate_manifests.py` 仍引用旧 ID `apple`，而规范环境目录定义的是 `xcode`。见 issue #34。

## 安全模型

强制规则见 [`AGENTS.md`](AGENTS.md)，其中包括：

- 不对不支持的组合进行静默回退；
- 不自动执行 `curl | sh` / `irm | iex`；
- 对已审查的工件路径进行 HTTPS/来源/完整性校验；
- 修改前先 staging，并防御路径穿越、符号链接与 reparse point；
- 拒绝接管外部或未管理的安装目录；
- 已验证的用户本地工件适配器不隐式永久修改 PATH；
- 权限提升仅限必要操作；
- 无法证明所有权时，删除操作 fail closed；
- 只有完整门禁通过后才单独提升支持状态。

安全卸载仍由 issue #3 跟踪。

## CI 与发布状态

仓库包含大量离线 Shell/PowerShell fixture 和 Python 语义验证器。但最近一次审计的 GitHub Actions 运行因外部账户/计费状态而在 **runner 启动之前** 被阻止，因此既不能视为“CI 通过”，也不能视为产品测试失败。

当前没有 GitHub Releases，也没有 Git tags。发布校验和/SBOM 仍由 issue #6 跟踪；扩展 Unix 目标验证由 issue #5 跟踪。

## 文档

- [审计后的仓库状态](docs/REPOSITORY-STATUS.md)
- [安装器架构](docs/installer-architecture.md)
- [系统原生入口](installers/README.md)
- [路线图](ROADMAP.md)
- [变更日志](CHANGELOG.md)
- [贡献指南](CONTRIBUTING.md)
- [支持](SUPPORT.md)
- [安全策略](SECURITY.md)
- [翻译策略](docs/TRANSLATIONS.md)

## 支持项目

[通过 PayPal 捐赠](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

[![PayPal 捐赠二维码](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## 许可证

MIT — 参见 [`LICENSE`](LICENSE)。
