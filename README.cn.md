# devkit-wulf

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Polski](README.pl.md) | [简体中文](README.cn.md) | [Русский](README.ru.md) | [Español](README.es.md)

一个安全、由清单驱动的多平台开发环境引导程序与编排器，面向 Windows、WSL2、Linux、macOS、BSD，以及经过明确研究的扩展 Unix 目标系统。

> **状态：** 当前为 1.0 之前的引导阶段。平台/环境组合在通过所需 CI 或目标系统验证门禁之前，均保持为 `experimental`。本仓库不会把未经验证的组合宣称为已支持。

## 设计

`devkit-wulf` 将以下职责彼此分离：

- 主机与体系结构检测；
- 软件包管理器选择；
- 环境元数据与支持策略；
- 安装策略；
- 不产生修改的计划模式；
- 系统修改与权限处理；
- 验证；
- 状态跟踪与回滚意识；
- CI / 安全门禁。

支持状态与执行策略独立建模。因此，一个组合可以是 `support: experimental`，同时使用 `strategy: package-manager`、`winget`、`official-script`、`official-archive`、`source`、`vm`、`container`、`wsl2` 或 `xcode`。

## 快速开始

### Linux / macOS / BSD / Unix

```sh
./bootstrap/linux.sh        # Linux / WSL2
./bootstrap/macos.sh        # macOS
./bootstrap/bsd.sh          # FreeBSD/OpenBSD/NetBSD/DragonFly
./bootstrap/solaris.sh      # Solaris/illumos
./bootstrap/aix.sh          # AIX

./bin/devkit-wulf detect
./bin/devkit-wulf list
./bin/devkit-wulf plan python
./bin/devkit-wulf install python --experimental
./bin/devkit-wulf verify python
./bin/devkit-wulf doctor
```

引导脚本只安装编排器所需的少量解析/工具依赖，不会安装开发配置文件。

### Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap\windows.ps1
.\bin\devkit-wulf.ps1 detect
.\bin\devkit-wulf.ps1 list
.\bin\devkit-wulf.ps1 plan python
.\bin\devkit-wulf.ps1 install python -Experimental
.\bin\devkit-wulf.ps1 verify python
.\bin\devkit-wulf.ps1 doctor
```

原生编排器支持 Windows PowerShell 5.1 和 PowerShell 7。基于 WinGet 的安装会在修改系统之前检查精确的软件包 ID，避免故意重复安装已存在的软件包。

### WSL2

请在所选 WSL 发行版内部运行 Linux CLI。WSL 发行版会独立于 Windows 主机进行检测。`devkit-wulf` 不会静默创建 WSL 发行版，也不会自动将 WSL1 转换为 WSL2。

若要先检查 Windows 侧的 WSL 更改计划：

```powershell
.\bootstrap\windows.ps1 -PlanWSL2 -Distribution Debian
```

修改 WSL 功能或发行版还需要提升权限的 shell，并显式传入 `-AllowSystemChange`。

在 WSL2 中由 Linux 工具操作的项目通常应存放在 Linux 文件系统中。原生 Windows 项目应保留在 Windows 一侧；跨文件系统 I/O 不被视为默认布局。

## 命令

```text
devkit-wulf detect
devkit-wulf list
devkit-wulf list --supported
devkit-wulf list --platform <platform>
devkit-wulf plan <environment>
devkit-wulf install <environment> [--experimental]
devkit-wulf verify <environment>
devkit-wulf remove <environment>
devkit-wulf install profile:<name> [--experimental]
devkit-wulf doctor
```

原生 Windows 使用等价的 PowerShell 参数 `-Experimental` 和 `-AcceptRemoteScript`。

`plan` 不修改系统。`install` 会拒绝 `unsupported` 组合；对于尚未通过全部支持门禁的组合，需要明确的实验性选择。尚未实现经验证专用适配器的策略会安全失败，而不是猜测安装方式。

## 初始环境

### 基础与语言

- `base`
- `cpp`
- `python`
- `node`
- `deno`
- `bun`
- `java`
- `dotnet`
- `go`
- `rust`
- `php`
- `ruby`

### 编辑器与 IDE

- `vscode`
- `visualstudio`
- `jetbrains`
- `eclipse`

### 移动开发 / 平台 SDK

- `android`
- `flutter`
- `apple`

### 容器 / 基础设施

- `docker`
- `podman`
- `kubectl`
- `opentofu`

## 配置文件

- `minimal`
- `web`
- `backend`
- `systems`
- `mobile`
- `devops`
- `full`
- `wsl-stable`
- `wsl-rolling`

`full` 配置文件绝不会自行启用 `experimental` 环境。`unsupported` 和 `target-only` 条目不会被转换为主机安装。

## 平台模型

主要实现目标：

- Windows 11 与仍受维护的 Windows 10 客户端；在具体环境支持的情况下使用 x64/ARM64；
- WSL2：Debian、Ubuntu、Arch Linux、openSUSE、Kali；
- Debian/Ubuntu/Mint/Kali/Raspberry Pi OS；
- Arch/Manjaro；
- Fedora/RHEL/Rocky/Alma；
- openSUSE；
- Alpine；
- Intel 与 Apple Silicon macOS。

研究/验证目标：

- FreeBSD、OpenBSD、NetBSD、DragonFly BSD；
- illumos、Oracle Solaris、AIX。

扩展 Unix 条目在权威目标系统验证之前保持为 `experimental` 或 `target-only`。交叉编译能力与主机支持分别建模。

## 安全模型

实现遵循 [`AGENTS.md`](AGENTS.md) 中的门禁，特别包括：

- 不对不支持的组合进行静默回退；
- 不自动执行 `curl | sh` / `irm | iex`；
- 在清单中记录来源与出处；
- 优先使用软件包管理器和官方厂商渠道；
- 远程脚本必须先下载并检查，再执行；
- 若上游提供完整性元数据，则校验和/签名不匹配会直接失败；
- 权限提升仅限真正需要的操作；
- `plan` 永不修改主机；
- 无法安全确认资源所有权时，拒绝破坏性卸载；
- 当上游要求时，Windows Server 的排除条件会独立于 Windows 客户端支持进行判断。

## 仓库结构

```text
AGENTS.md               治理契约与强制门禁
bin/                    面向用户的 POSIX 和 PowerShell 编排器
bootstrap/              最小化主机引导脚本
manifests/              平台/环境目录与模式定义
profiles/               可组合的环境选择
research/               带日期的上游支持/来源研究
scripts/                验证/安全辅助工具
tests/                  清单与 CLI 测试
.github/workflows/       CI 门禁
```

## 当前自动化边界

软件包管理器策略以及部分 `official-script` 策略已有可执行适配器。`official-archive`、产品专用 `manual`、源码构建、VM 和容器策略会显示在计划中，但在每个产品的下载、完整性、所有权、PATH 和卸载契约实现之前，会有意安全失败。

这一边界可防止广泛的平台矩阵退化为未经验证的下载命令集合。

## 上游研究

初始支持矩阵于 **2026-08-10** 基于上游第一方文档更新。参见 [`research/upstream-sources.md`](research/upstream-sources.md)。运行时版本与 EOL 信息不会被视为永久有效；清单会记录研究日期，在涉及版本的修改前必须重新验证。

推荐的平台/环境主机与执行域策略见 [`docs/platform-strategy.md`](docs/platform-strategy.md)。分阶段实现与支持提升状态见 [`ROADMAP.md`](ROADMAP.md)。

## 文档与社区

- [贡献指南](CONTRIBUTING.md)
- [支持与问题报告指南](SUPPORT.md)
- [安全策略](SECURITY.md)
- [翻译策略](docs/TRANSLATIONS.md)
- [路线图](ROADMAP.md)

## 支持项目

如果 `devkit-wulf` 对你有帮助，可以通过 PayPal 支持项目继续开发：

<a href="https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U" target="_blank"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" alt="通过 PayPal 捐赠" title="PayPal - The safer, easier way to pay online!" /></a>

[通过 PayPal 捐赠](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

扫描或点击二维码即可打开同一个 PayPal 捐赠页面：

[![PayPal 捐赠二维码](docs/assets/paypal-qr.png)](https://www.paypal.com/donate/?hosted_button_id=U823TB85A693U)

## 许可证

MIT — 参见 [`LICENSE`](LICENSE)。
