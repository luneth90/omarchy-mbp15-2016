# omarchy-mbp15-2016

[English](README.md) | **简体中文**

> 专为 MacBook Pro（15寸，2016款 / `MacBookPro13,3`）打造的 macOS + Omarchy (Arch Linux) 双系统硬件驱动、显卡切换与温控降温自动化套件。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Target: MacBookPro13,3](https://img.shields.io/badge/硬件型号-MacBookPro13%2C3-blue.svg)](#硬件规格与支持矩阵)
[![Setup: Dual Boot](https://img.shields.io/badge/安装形态-macOS%20%2B%20Omarchy%20双系统-brightgreen.svg)](#-重要安装须知必须双系统切勿抹盘格式化安装)
[![OS: Omarchy](https://img.shields.io/badge/操作系统-Omarchy%20%2F%20Arch-orange.svg)](https://omarchy.org)
[![Kernel: Linux 7.1.x/7.2.x](https://img.shields.io/badge/内核-Linux%207.1.x%2F7.2.x-brightgreen.svg)](#系统环境要求)

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
- **发热严重与待机高耗电**：AMD 独显常开且显存频率锁死，空载功耗高达 10~15W，外壳极度烫手；
- **Touch Bar** 默认黑屏不亮，或因内核早期的初始化时序竞争导致开机死锁挂起；
- **Wi-Fi** 默认加载占位伪 MAC 地址（`00:90:4c:...`），导致 5GHz（Band 2）频段被锁死，且存在严重延迟抖动；
- **内置四扬声器与 3.5mm 耳机接口** 无声；
- **休眠 / 唤醒** 极不稳定，常因 AMD 独立显卡与 NVMe 控制器的 PCIe D3cold 电源状态冲突导致黑屏死机。

**omarchy-mbp15-2016** 提供了一套全自动、高健壮性的硬件修复、温控降温与诊断套件，一键解决上述所有硬件驱动与系统配置问题，且绝不破坏已有磁盘分区，安全保护 macOS 原生系统。

---

## 硬件规格与支持矩阵

| 硬件组件 | 硬件标识符 (ID) | Linux 驱动 / 子系统 | 适配状态 |
| :--- | :--- | :--- | :---: |
| **设备型号** | `MacBookPro13,3` (15寸, 2016款) | DMI `product_name` | 完美支持 |
| **安全芯片** | Apple T1 协处理器 (`05ac:8600`) | `appleibridge` (延迟加载) | 正常运行 |
| **Touch Bar** | 2170x60 OLED 触控条 | `apple-ib-tb` DKMS + `touchbar.service` | 正常运行 |
| **显卡与切换** | Intel HD 530 (核显) + AMD Radeon Pro (独显) | `i915` + `amdgpu` + EFI `gpu-power-prefs` | 完美支持 (支持一键无缝切换) |
| **风扇与温控** | Apple SMC 双风扇 + mbpfan 调优温控 | `applesmc` + `coretemp` + `mbpfan` | 完美支持 (主动控温 + 压制睿频) |
| **无线网卡** | Broadcom BCM43602 (`14e4:43ba`) | `brcmfmac` + 定制 NVRAM 固件 | 正常运行 (2.4G / 5G) |
| **音频声卡** | Cirrus Logic CS8409 HDA | `snd_hda_macbookpro` DKMS | 正常运行 |
| **键盘 / 触控板** | Apple SPI 键盘与 Force Touch 触控板 | 主线 `applespi` 内核模块 | 原生支持 |
| **电源 / 休眠** | Apple 原装 NVMe + PCIe 电源管理 | `s2idle` + NVMe D3cold 动态接管 | 稳定休眠 |
| **摄像头** | FaceTime 高清摄像头 | `uvcvideo` / V4L2 | 原生支持 |

---

## 核心功能与技术特性

- **彻底解决发热与显卡自由切换**：
  - **解耦确认**：Touch Bar 为独立 USB HID 协处理器，休眠机制依赖 NVMe 控制与 `s2idle`，**与 AMD 显卡完全解耦**；
  - **核显低温长续航模式 (`gpu-igpu`)**：通过 EFI 原生指令让内屏改由 Intel HD 530 驱动，AMD 独显彻底断电休眠，整机待机功耗降低 10~15W，温度骤降至 38~45°C 冰凉状态；
  - **独显外接屏模式 (`gpu-dgpu`)**：随时一键切回 AMD 独显，完整支持通过 USB-C 外接大屏显示器；
  - **`mbpfan` 激进散热服务**：改写苹果原生过于保守的迟钝风扇曲线，提前排热，告别烫手机壳；
  - **CPU 睿频热量抑制**：可选关闭日常办公无意义的 45W Turbo Boost 瞬时发热峰值。
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
- **稳定可靠的休眠与唤醒支持**：
  - 配置 `systemd-sleep` 使用 `freeze` / `s2idle`；
  - 在 Limine 引导器中自动注入 `mem_sleep_default=s2idle`、`intel_iommu=on`、`iommu=pt` 与 `pcie_ports=compat` 参数；
  - 部署 `mbp15-nvme-d3cold.service`，开机及休眠前动态关闭 Apple NVMe 控制器的 `d3cold_allowed`，避免其在休眠恢复时卡死。
- **安全第一与完整回滚机制**：
  - 严密的设备型号（`MacBookPro13,3`）与 T1 状态预检；
  - 绝不重新划分磁盘，保留 macOS、Apple EFI 和 APFS 分区安全；
  - 提供一键回滚命令（`rollback`），原样恢复系统原本配置。

---

## 显卡切换与彻底退烧指南

### 1. 为什么 MBP13,3 默认发热极为严重？
1. **AMD 独显待机功耗锁死**：Linux 启动时 EFI 默认使用 AMD 独显驱动内屏。AMD Polaris 驱动在驱动 2880×1800 Retina 高分屏时，因消隐时序保护机制，强制将显存频率锁死在最高档（1270MHz，`3D_FULL_SCREEN` 模式），导致空载即持续发热 10W+；
2. **风扇调控过于迟钝**：苹果 SMC 原厂固件为追求极致静音，温度到达 65~75°C 时风扇仍然只转 2000~3000 RPM，无法及时排热；
3. **Intel Turbo Boost 瞬时功耗尖峰**：14nm Skylake i7 瞬时睿频功耗可冲到 45W+。

### 2. 一步到位：切换为 Intel 核显独占（推荐日常不接外屏使用）
如果您平时使用内屏、不需要外接 Type-C 显示器，直接切换为 Intel 核显独占是**最彻底的退烧方式**：

```bash
# 1. 部署 mbpfan 调优曲线与 CPU 降温服务
sudo ./omarchy-mbp15-2016.sh install-cooling

# 2. 切换 EFI 显卡偏好为 Intel 核显
sudo ./omarchy-mbp15-2016.sh gpu-igpu

# 3. 重启生效
sudo reboot
```

> [!TIP]
> **日后如需外接显示器**：
> MacBookPro13,3 的外接 USB-C 显示输出物理连接在 AMD 独显上。如果需要外接大屏幕，只需运行：
> ```bash
> sudo ./omarchy-mbp15-2016.sh gpu-dgpu
> sudo reboot
> ```
> 即可瞬间切回独显模式。

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

### 3. 安装与配置驱动

脚本提供灵活的安装模式，请根据具体需求选择执行：

#### 选项 A：一步到位全量安装（推荐首次使用，含核显退烧）
一条命令自动完成全部硬件驱动与退烧配置（注入 macOS 物理 MAC 激活 5GHz Wi-Fi、编译 Cirrus 声卡 DKMS、编译 Apple T1 Touch Bar 驱动与服务、部署休眠防死锁服务、部署 mbpfan 散热降温与幽灵屏屏蔽，并直接切换 EFI 为 Intel 核显低温模式）：
```bash
sudo ./omarchy-mbp15-2016.sh install --wifi-mac AA:BB:CC:DD:EE:FF --switch-igpu
```

> [!NOTE]
> 如果您需要经常外接显示器，可以去掉 `--switch-igpu` 参数，安装将默认保持 AMD 独显输出。日后也可随时通过 `gpu-igpu` 和 `gpu-dgpu` 命令无缝切换。

#### 选项 B：全量安装但跳过 Wi-Fi 固件更新
执行声卡、Touch Bar、休眠、散热降温及可选核显切换，但保留当前 Wi-Fi NVRAM 固件不作更改：
```bash
sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram --switch-igpu
```

#### 选项 C：定向部署散热降温套件（秒级极速）
仅部署针对 MBP13,3 调优的 `mbpfan` 风扇温控曲线、CPU 功耗限制与幽灵屏屏蔽配置：
```bash
sudo ./omarchy-mbp15-2016.sh install-cooling
```

#### 安装命令功能对比

| 命令 | 5GHz Wi-Fi 校准 | Cirrus 声卡驱动 | Touch Bar 驱动 | 休眠/NVMe 防死锁 | mbpfan 调优散热 | EFI 核显切换 (退烧) | 预计耗时 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `install ... --switch-igpu` | ✅ 注入真实 MAC | ✅ 编译部署 | ✅ 编译部署 | ✅ 部署启用 | ✅ 部署启用 | ✅ 设为 Intel 核显 (独显 0W) | 约 2~3 分钟 |
| `install --wifi-mac <MAC>` | ✅ 注入真实 MAC | ✅ 编译部署 | ✅ 编译部署 | ✅ 部署启用 | ✅ 部署启用 | ➖ 保持当前显卡 | 约 2~3 分钟 |
| `install --skip-wifi-nvram` | ❌ 跳过 | ✅ 编译部署 | ✅ 编译部署 | ✅ 部署启用 | ✅ 部署启用 | ➖ 保持当前显卡 | 约 2~3 分钟 |
| `install-cooling` | ❌ 跳过 | ❌ 跳过 | ❌ 跳过 | ❌ 跳过 | ✅ 部署启用 | ❌ 跳过 | **数秒内** |
| `install-suspend` | ❌ 跳过 | ❌ 跳过 | ❌ 跳过 | ✅ 部署启用 | ❌ 跳过 | ❌ 跳过 | **数秒内** |
| `gpu-igpu` | ❌ 跳过 | ❌ 跳过 | ❌ 跳过 | ❌ 跳过 | ❌ 跳过 | ✅ 设为 Intel 核显 | **数秒内** |

### 4. 重启系统

```bash
sudo reboot
```

### 5. 验证硬件门禁

重启进入系统后，执行自动化验证检查：
```bash
sudo ./omarchy-mbp15-2016.sh verify
```

---

## 脚本命令速查

| 指令 | 作用说明 |
| :--- | :--- |
| `sudo ./omarchy-mbp15-2016.sh status` | 查看当前内核、显卡运行模式、温控、引导参数以及各项外设驱动运行状态 |
| `sudo ./omarchy-mbp15-2016.sh install --wifi-mac <MAC>` | 【推荐】全量安装所有依赖包、校准 5GHz Wi-Fi、编译声卡与 Touch Bar、部署休眠与散热配置 |
| `sudo ./omarchy-mbp15-2016.sh install-cooling` | 定向部署 `mbpfan` 定制温控曲线服务及 CPU 省电降温策略 |
| `sudo ./omarchy-mbp15-2016.sh gpu-igpu` | 将 EFI 显卡偏好设置为 Intel HD 530 核显独占（彻底退烧，需重启） |
| `sudo ./omarchy-mbp15-2016.sh gpu-dgpu` | 将 EFI 显卡偏好恢复为 AMD Radeon Pro 独显（外接屏幕时使用，需重启） |
| `sudo ./omarchy-mbp15-2016.sh install-suspend` | 定向秒级部署 `mbp15-nvme-d3cold.service` 与 Limine s2idle/IOMMU 休眠防死锁配置 |
| `sudo ./omarchy-mbp15-2016.sh install-touchbar` | 单独重新编译与部署 Touch Bar 与 Apple T1 iBridge DKMS 驱动与自启服务 |
| `sudo ./omarchy-mbp15-2016.sh install-audio` | 单独重新编译与部署 Cirrus Logic CS8409 音频 DKMS 驱动 |
| `sudo ./omarchy-mbp15-2016.sh verify` | 自动检查显卡模式、温控、Wi-Fi MAC、键盘触控板、声卡、Touch Bar 及 NVMe 状态 |
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
- [mbpfan](https://github.com/linux-on-mac/mbpfan) by linux-on-mac（MacBook 风扇温控守护进程）
- [gpu-switch](https://github.com/0xbb/gpu-switch) by 0xbb（MacBook Pro 双显卡 EFI 切换逻辑）
- [Omarchy](https://omarchy.org) 团队及 Arch Linux 社区。

---

## 开源协议

本项目采用 [MIT 许可证](LICENSE) 开源。
