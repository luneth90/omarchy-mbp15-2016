# omarchy-mbp15-2016

[English](README.md) | **简体中文**

> 专为 MacBook Pro（15寸，2016款 / `MacBookPro13,3`）打造的 macOS + Omarchy (Arch Linux) 双系统硬件驱动与系统适配自动化套件。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Target: MacBookPro13,3](https://img.shields.io/badge/硬件型号-MacBookPro13%2C3-blue.svg)](#硬件规格与支持矩阵)
[![Setup: Dual Boot](https://img.shields.io/badge/安装形态-macOS%20%2B%20Omarchy%20双系统-brightgreen.svg)](#-重要安装须知必须双系统切勿抹盘格式化安装)
[![OS: Omarchy](https://img.shields.io/badge/操作系统-Omarchy%20%2F%20Arch-orange.svg)](https://omarchy.org)
[![Kernel: Linux 7.1.x](https://img.shields.io/badge/内核-Linux%207.1.x-brightgreen.svg)](#系统环境要求)

---

## ⚠️ 重要安装须知：必须双系统，切勿抹盘格式化安装！

> [!CAUTION]
> **本项目必须在保留原有 macOS 的双系统（Dual Boot）环境下使用！切勿全盘抹除/格式化安装单系统 Linux！**
> 
> - **Touch Bar 固件依赖**：MacBook Pro 2016 款的 Touch Bar 触控条由独立的 **Apple T1 安全协处理器（iBridge）** 驱动，T1 内部运行独立的 embeddedOS/bridgeOS 系统。设备开机引导时，T1 芯片必须依赖 Apple 原厂 EFI 与 macOS 分区提供的专属固件进行初始化与引导。
> - **抹盘格式化安装的后果**：如果直接抹除整块硬盘（Clean Install / 单系统格式化安装 Linux），**系统将彻底缺失 Touch Bar 运行所需的底层固件**。T1 协处理器将因无法获取固件而无法正常初始化，甚至会掉入 DFU 恢复模式（在 Linux 下设备 ID 会显示为 `05ac:1281` 而非正常的 `05ac:8600`）。在此状态下，**任何 Linux 驱动都无法点亮 Touch Bar，触控条将彻底黑屏失效**。
> - **推荐双系统安装流程**：
>   1. 正常进入 macOS，打开系统自带的**磁盘工具**（Disk Utility）；
>   2. 选中“Macintosh HD”所在的 APFS 容器进行“分区/调整大小”，缩小 macOS 空间，为 Omarchy 腾出未分配空闲空间（建议划分 60GB 以上）；
>   3. 顺便在 macOS 终端中运行 `networksetup -getmacaddress en0`，记录下真实的 Wi-Fi 物理 MAC 地址；
>   4. 插入 Omarchy / Arch 安装 U 盘开机，**仅将 Linux 安装至刚才划分出的空闲分区**，务必完整保留 macOS 容器、Recovery 恢复分区与 Apple 原厂 EFI 分区；
>   5. 进入 Omarchy 后，再克隆并运行本项目脚本一键激活所有驱动。

---

## 概述

在苹果 2016 款配备 Touch Bar 的机器上运行 Linux，历来面临极具挑战的硬件适配难题。15 寸 2016 款 MacBook Pro（`MacBookPro13,3`）拥有高度定制的硬件拓扑：Apple T1 安全协处理器（iBridge）、动态 OLED Touch Bar、双显卡架构（Intel HD 530 + AMD Radeon Pro 450/455/460，经由 `apple_gmux` 硬件切换器）、Cirrus Logic CS8409 高清音频编解码器以及博通 BCM43602 PCIe 无线网卡。

在官方原版 Linux 或常规安装下：
- **Touch Bar** 默认黑屏不亮，或因内核早期的初始化时序竞争导致开机死锁挂起；
- **Wi-Fi** 默认加载占位伪 MAC 地址（`00:90:4c:...`），导致 5GHz（Band 2）频段被锁死，且存在严重延迟抖动；
- **内置四扬声器与 3.5mm 耳机接口** 无声；
- **休眠 / 唤醒** 极不稳定，常因 AMD 独立显卡与 NVMe 控制器的 PCIe D3cold 电源状态冲突导致黑屏死机。

**omarchy-mbp15-2016** 提供了一套全自动、高健壮性的硬件修复与诊断套件，一键解决上述所有硬件驱动与系统配置问题，且绝不破坏已有磁盘分区，安全保护 macOS 原生系统。

---

## 硬件规格与支持矩阵

| 硬件组件 | 硬件标识符 (ID) | Linux 驱动 / 子系统 | 适配状态 |
| :--- | :--- | :--- | :---: |
| **设备型号** | `MacBookPro13,3` (15寸, 2016款) | DMI `product_name` | 完美支持 |
| **安全芯片** | Apple T1 协处理器 (`05ac:8600`) | `appleibridge` (延迟加载) | 正常运行 |
| **Touch Bar** | 2170x60 OLED 触控条 | `apple-ib-tb` DKMS + `touchbar.service` | 正常运行 |
| **无线网卡** | Broadcom BCM43602 (`14e4:43ba`) | `brcmfmac` + 定制 NVRAM 固件 | 正常运行 (2.4G / 5G) |
| **音频声卡** | Cirrus Logic CS8409 HDA | `snd_hda_macbookpro` DKMS | 正常运行 |
| **键盘 / 触控板** | Apple SPI 键盘与 Force Touch 触控板 | 主线 `applespi` 内核模块 | 原生支持 |
| **显卡** | Intel HD 530 + AMD Radeon Pro | `i915` + `amdgpu` + `apple_gmux` | 正常运行 |
| **电源 / 休眠** | Apple 原装 NVMe + PCIe 电源管理 | `s2idle` + NVMe D3cold 动态接管 | 稳定休眠 |
| **摄像头** | FaceTime 高清摄像头 | `uvcvideo` / V4L2 | 原生支持 |
| **风扇与温控** | Apple SMC (双风扇 + 温度传感器) | `applesmc` + `coretemp` | 原生支持 (固件闭环控温，无需 mbpfan) |

---

## 核心功能与技术特性

- **Touch Bar 与 T1 稳定性保障**：
  - 自动拉取、编译并安装 `appleibridge` 和 `apple-ib-tb` DKMS 内核模块；
  - 黑名单屏蔽内核早期加载，彻底消除开机时序死锁风险；
  - 注册 `touchbar.service` 服务，开机后自动点亮 Touch Bar（默认多媒体控制条，按住 Fn 键无缝切换 F1–F12）；
  - 部署 `/usr/lib/systemd/system-sleep/90-mbp-touchbar-resume` 脚本，休眠唤醒后自动重载驱动并复位显示。
- **5GHz Wi-Fi 全频段校准激活**：
  - 下载精准匹配的 BCM43602 NVRAM 校准固件；
  - 注入 macOS 原生出厂物理 MAC 地址，解除 5GHz (Band 2) 频段锁定，彻底解决高延迟与掉线问题。
- **Cirrus CS8409 高清音频驱动自动部署**：
  - 自动集成并编译 `snd_hda_macbookpro`，支持 PipeWire/ALSA 完整接管内置四扬声器与耳机口输出。
- **风扇与温控闭环管理（固件级自动接管）**：
  - Apple SMC 硬件控制器与主线 `applesmc` / `coretemp` 驱动原生联动，双风扇与各区温控传感器开箱即用；
  - 默认由 SMC 原厂固件闭环控温，根据内部热度自动调节风扇转速与硬件过热保护，无需额外常驻守护进程（即 `mbpfan is not needed`；如需激进低温降温曲线也可按需选装 `mbpfan`）；
  - 脚本与验证门禁自动检测 Apple SMC 状态、双风扇 RPM 实时转速与工作模式。
- **稳定可靠的休眠与唤醒支持**：
  - 配置 `systemd-sleep` 使用 `freeze` / `s2idle`；
  - 在 Limine 引导器中自动注入 `mem_sleep_default=s2idle`、`intel_iommu=on`、`iommu=pt` 与 `pcie_ports=compat` 参数；
  - 部署 `mbp15-nvme-d3cold.service`，开机及休眠前动态关闭 Apple NVMe 控制器的 `d3cold_allowed`，避免其在休眠恢复时与独显冲突挂死。
- **安全第一与完整回滚机制**：
  - 严密的设备型号（`MacBookPro13,3`）与 T1 状态预检（检测 `05ac:8600`，若因全盘格式化丢失固件导致 T1 陷入恢复模式 `05ac:1281` 则立即拦截熔断并警告）；
  - 绝不重新划分磁盘，保留 macOS、Apple EFI 和 APFS 分区安全；
  - 提供一键回滚命令（`rollback`），原样恢复系统原本配置。

---

## 系统环境要求

- **系统形态**：**macOS + Omarchy 双系统**（必须保留原有 macOS 与 Apple EFI 分区，切勿抹盘全盘格式化）。
- **机型**：Apple MacBook Pro 15-inch（Late 2016，带 Touch Bar，机型代号 `MacBookPro13,3`）。
- **操作系统**：[Omarchy](https://omarchy.org) 或基于 Arch Linux 的发行版。
- **内核版本**：Linux 7.1.x 系列（需已安装对应内核头文件 `linux-headers`）。
- **引导器**：Limine 引导器（依赖 `limine-entry-tool` 与 `limine-update`）。
- **权限**：管理员权限（`sudo`）。

---

## 快速使用

### 1. 克隆代码仓库

```bash
git clone https://github.com/luneth90/omarchy-mbp15-2016.git
cd omarchy-mbp15-2016
chmod +x omarchy-mbp15-2016.sh
```

### 2. 检查当前硬件与驱动状态

```bash
sudo ./omarchy-mbp15-2016.sh status
```

### 3. 一键安装与配置驱动

> [!IMPORTANT]
> 1. **双系统环境**：请确保本机保留了 macOS 原厂分区与固件环境，切勿抹盘全盘格式化，否则会导致 Touch Bar 缺失底层固件而无法驱动。
> 2. **Wi-Fi 5GHz 校准**：要完整激活 5GHz Wi-Fi 频段，需要提供你这台机器在 macOS 下的真实 Wi-Fi MAC 地址（可在 macOS 终端执行 `networksetup -getmacaddress en0` 或路由器后台查询）。切勿使用以 `00:90:4c:` 开头的占位 MAC。

脚本提供三种不同的安装模式，请根据具体需求选择执行：

#### 选项 A：全量完整安装（推荐首次使用）
一键配置所有外设（注入 macOS 物理 MAC 激活 5GHz Wi-Fi、编译 Cirrus 声卡 DKMS、编译 Apple T1 Touch Bar 驱动与服务、部署休眠与 NVMe 防死锁服务）：
```bash
sudo ./omarchy-mbp15-2016.sh install --wifi-mac AA:BB:CC:DD:EE:FF
```

#### 选项 B：全量安装但跳过 Wi-Fi 固件更新
执行声卡、Touch Bar 与休眠服务的全套安装，但保留当前 Wi-Fi NVRAM 固件不作更改（适用于已校准过 MAC 或暂无真实 MAC 的情况）：
```bash
sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram
```

#### 选项 C：仅安装休眠与 NVMe 防黑屏服务（秒级轻量定向安装）
跳过耗时的声卡与 Touch Bar 驱动拉取和 DKMS 编译，仅部署 `mbp15-nvme-d3cold.service`，注入 Limine `s2idle` 与 IOMMU 引导参数，防止合盖唤醒黑屏死机：
```bash
sudo ./omarchy-mbp15-2016.sh install-suspend
```

#### 安装命令功能对比

| 命令 | 5GHz Wi-Fi 校准 | Cirrus 声卡驱动 | Touch Bar 驱动 | 休眠/NVMe 防死锁服务 | 预计耗时 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `install --wifi-mac <MAC>` | ✅ 注入真实 MAC | ✅ 编译部署 | ✅ 编译部署 | ✅ 部署启用 | 约 2~3 分钟 |
| `install --skip-wifi-nvram` | ❌ 跳过 | ✅ 编译部署 | ✅ 编译部署 | ✅ 部署启用 | 约 2~3 分钟 |
| `install-suspend` | ❌ 跳过 | ❌ 跳过 | ❌ 跳过 | ✅ 部署启用 | **数秒内** |

### 4. 重启系统

```bash
sudo reboot
```

### 5. 验证硬件门禁

重启进入系统后，执行自动化验证检查：
```bash
sudo ./omarchy-mbp15-2016.sh verify
```

### 6. 测试休眠唤醒

在进行物理盒盖休眠前，可先通过阶段性模拟测试验证驱动挂起与恢复流程：
```bash
sudo ./omarchy-mbp15-2016.sh pm-test
```

还可以随时审查上一启动周期的休眠与唤醒内核日志：
```bash
sudo ./omarchy-mbp15-2016.sh previous-boot
```

---

## 脚本命令速查

| 指令 | 作用说明 |
| :--- | :--- |
| `sudo ./omarchy-mbp15-2016.sh status` | 查看当前内核、引导参数以及各项外设驱动运行状态 |
| `sudo ./omarchy-mbp15-2016.sh install --wifi-mac <MAC>` | 【推荐】全量安装所有依赖包、校准 5GHz Wi-Fi、编译声卡与 Touch Bar、部署休眠与引导配置 |
| `sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram` | 全量安装声卡、Touch Bar 与休眠配置，但跳过 Wi-Fi NVRAM 固件更新 |
| `sudo ./omarchy-mbp15-2016.sh install-suspend` | 定向秒级部署 `mbp15-nvme-d3cold.service` 与 Limine s2idle/IOMMU 休眠防死锁配置 |
| `sudo ./omarchy-mbp15-2016.sh install-touchbar` | 单独重新编译与部署 Touch Bar 与 Apple T1 iBridge DKMS 驱动与自启服务 |
| `sudo ./omarchy-mbp15-2016.sh install-audio` | 单独重新编译与部署 Cirrus Logic CS8409 音频 DKMS 驱动 |
| `sudo ./omarchy-mbp15-2016.sh verify` | 自动检查 Wi-Fi MAC、键盘触控板、声卡、Touch Bar、SMC 风扇与温控及 NVMe 状态 |
| `sudo ./omarchy-mbp15-2016.sh pm-test` | 启用 `pm_test=devices` 安全测试外设驱动的休眠与唤醒 |
| `sudo ./omarchy-mbp15-2016.sh previous-boot` | 检索上一启动周期的 systemd sleep 与 dmesg 休眠挂起日志 |
| `sudo ./omarchy-mbp15-2016.sh rollback` | 完整还原所有修改的配置文件，移除所部署的服务并刷新引导 |

---

## 卸载与回滚

如果需要恢复到运行脚本之前的系统初始状态，只需执行：

```bash
sudo ./omarchy-mbp15-2016.sh rollback
sudo reboot
```

---

## 上游致谢

本项目离不开开源社区对苹果硬件的逆向探索与贡献：
- [omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1) by nohzafk（Touch Bar 与 T1 iBridge Linux 驱动）
- [snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) by davidjo（Cirrus Logic CS8409 音频驱动）
- [Omarchy](https://omarchy.org) 团队及 Arch Linux 社区。

---

## 开源协议

本项目采用 [MIT 许可证](LICENSE) 开源。
