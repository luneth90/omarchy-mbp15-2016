# omarchy-mbp15-2016

[English](README.md) | **简体中文**

面向 `MacBookPro13,3`（15 英寸，2016，Touch Bar/T1）的 Omarchy/Arch 硬件安装与诊断脚本。

当前代码审查与自动测试并不是目标机器上的实机认证：固定的 T1 配方上游报告是在另一款 T1 Mac 上验证，`MacBookPro13,3` 仍必须按下述阶段逐项实测。脚本把 DKMS 安装限制在已审查的 Linux `7.1.x/7.2.x` 范围，超出后应先重新审计，而不是强行安装。

## 先读：iGPU 不是普通的一键切换

在 `MacBookPro13,3` 上，从非 macOS 引导时固件通常只暴露 AMD 独显。仅写入 `gpu-power-prefs`，却没有让引导器执行 `apple_set_os`，可能导致 Intel 核显不可用、内屏黑屏。外接 USB-C 视频输出通常又连接到 AMD 独显，因此 iGPU 模式下不能把外接屏当作救援显示器。

本版脚本因此做了这些限制：

- 不再提供一次完成驱动、挂起、音频和显卡切换的全量安装。
- GPU 命令只接受 Apple Radeon Pro 450/455/460（`1002:67ef`，子系统 `106b:0167/0166/0160`），其他硬件直接拒绝。
- `gpu-igpu` 只有在 `00:02.0` 已可见、已绑定 `i915`、没有外接屏、没有旧版显示或强制休眠/IOMMU 配置时才允许执行。
- GPU 命令只设置下一次启动的 EFI 偏好；不会热切换显卡，不会写 `AQ_DRM_DEVICES`，不会猜测 `card0/card1` 或 `eDP-1/eDP-2`。
- 第一次 iGPU 启动默认把再下一次启动预设回 AMD；只有桌面验证成功并执行 `gpu-confirm-igpu --yes` 后才永久保留 Intel 偏好。
- 首次更改 EFI 前保存原值；`rollback` 会恢复原值。
- GPU 更改和实际挂起测试都要求显式 `--yes`。

上游硬件说明：[Dunedan/mbp-2016-linux](https://github.com/Dunedan/mbp-2016-linux)。EFI 切换原理参考：[0xbb/gpu-switch](https://github.com/0xbb/gpu-switch)。

> 必须保留 macOS、Apple EFI 和恢复环境。脚本不会分区，但抹除 macOS/T1 固件环境可能使 Touch Bar 进入 `05ac:1281` DFU 状态。

## 可靠安装顺序

每个阶段完成后先验证，再进行下一阶段。不要在无人值守或没有物理接触机器时测试重启/挂起。

### 0. 准备恢复路径

1. 确认 macOS 和 Apple 启动选择器仍可启动。
2. 保存工作，拔掉所有 USB-C 显示器、扩展坞和非必要外设。
3. 在 macOS 记录真实 Wi-Fi MAC：`networksetup -getmacaddress en0`。
4. 确认当前 Linux 能从启动菜单选择旧内核或 AMD 路径。

### 1. 基础预检与依赖

```bash
chmod +x omarchy-mbp15-2016.sh
sudo ./omarchy-mbp15-2016.sh status
sudo ./omarchy-mbp15-2016.sh install-base
```

`install-base` 会检查 DMI 型号、T1 状态和当前运行内核的精确 headers。它不会安装硬件驱动或修改引导项。

### 2. Touch Bar（先单独完成）

```bash
sudo ./omarchy-mbp15-2016.sh install-touchbar
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-touchbar
```

驱动源码固定到脚本内记录的提交。模块延迟加载以避开早期启动竞争；脚本不会在阻塞式 `system-sleep` 钩子中自动卸载 HID 内核模块，以免恢复链卡死。确认正常启动、键盘/触控板和 Touch Bar 工作后再继续；若唤醒后只有 Touch Bar 失效，先收集日志，不要用自动 `rmmod` 钩子掩盖问题。

### 3. 最小挂起配置

```bash
sudo ./omarchy-mbp15-2016.sh install-suspend
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-suspend
```

此阶段只加入 `pcie_ports=compat`，并启用针对实际 NVMe PCI 地址的 D3cold 服务；不再强制 `s2idle`、IOMMU 或覆盖其他 Omarchy 服务。此时不要直接做真实挂起。

### 4. 清理旧版显示与强制休眠配置

如果曾运行旧版脚本，务必执行：

```bash
sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all --dry-run
sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all
sudo reboot
```

它先备份再移除旧脚本的精确 `AQ_DRM_DEVICES=/dev/dri/cardN:...`、`video=eDP-2:d`、固定 Hyprland monitor 注入、`30-mbp15-suspend.conf` 中的强制 `freeze/s2idle`，以及旧版加入的 `mem_sleep_default=s2idle`、`iommu=pt`、`intel_iommu=on`。混合配置中的其他内容会保留；在救援环境以纯 root 执行时会扫描 `/home/*`。

### 5. 在引导器中配置 `apple_set_os`

这是脚本故意不自动完成的独立门禁，因为具体步骤取决于你的 EFI/引导器布局。按照所用引导器的说明，让 Linux 启动链在每次 iGPU 启动前执行受信任的 `apple_set_os.efi`，然后先保持 AMD 偏好重启。上游的 `MacBookPro13,3` 实例使用 rEFInd，并在 `refind.conf` 中设置 `spoof_osx_version 10.12`；请先核对你的 rEFInd 版本和配置语法，不要把该设置直接套到其他引导器。

启动后必须满足：

```bash
lspci -nnk -s 00:02.0
```

输出应显示 Intel 显卡，且 `Kernel driver in use: i915`。不满足就不要运行 `gpu-igpu`。

### 6. 选择 iGPU，并立即验证一次启动

拔掉外接屏后运行：

```bash
sudo ./omarchy-mbp15-2016.sh gpu-igpu --yes
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-gpu
hyprctl monitors all
sudo ./omarchy-mbp15-2016.sh gpu-confirm-igpu --yes
```

`gpu-igpu` 会安装一次性保护：首次 Intel 启动到达 `multi-user.target` 后，自动把下一次启动设回 AMD。只有确认桌面、键盘和触控板正常后才运行 `gpu-confirm-igpu --yes`。如果内屏黑屏但系统仍启动，等待一分钟后强制重启，应该回到 AMD；若内核在保护服务启动前就锁死，则使用 Apple 启动选择器/macOS 或已知可用的恢复环境。不要手工假定内屏叫 `eDP-1` 或 `eDP-2`。

需要手动恢复 AMD 时运行：

```bash
sudo ./omarchy-mbp15-2016.sh gpu-dgpu --yes
sudo reboot
```

若 Linux 无法进入，可从可写入 efivarfs 的救援环境恢复脚本保存在 `/var/lib/mbp15-2016-t1-touchbar-fix/` 的 EFI 备份；不要反复盲目重启。

### 7. Wi-Fi、降温和可选风扇服务

```bash
sudo ./omarchy-mbp15-2016.sh install-wifi AA:BB:CC:DD:EE:FF
sudo reboot
sudo ./omarchy-mbp15-2016.sh install-cooling
```

Wi-Fi 文件固定来源并校验 SHA-256。`install-cooling` 只设置 CPU 省电/禁用 Turbo 策略，不修改显示配置。Apple SMC 本身会管理风扇；只有确实需要主动风扇曲线时才安装：

```bash
sudo ./omarchy-mbp15-2016.sh install-mbpfan
```

### 8. 挂起测试（最后、现场执行）

仅在当前内屏由 Intel 驱动、没有外接屏、静态门禁通过时：

```bash
sudo ./omarchy-mbp15-2016.sh pm-test --yes
```

它使用 `pm_test=devices`，仍不等同于真实低功耗挂起。保存工作后再手动执行一次 `sudo systemctl suspend`；若恢复失败，重启后用 `previous-boot` 查看上一启动周期日志。

### 9. 音频 DKMS（最后且可选）

```bash
sudo ./omarchy-mbp15-2016.sh install-audio --ack-kernel-risk
sudo reboot
```

音频驱动存在随内核变化而崩溃的上游报告，因此脚本固定源码提交、要求匹配 headers，并强制风险确认，但不能保证任意未来内核兼容。安装后先测试扬声器/耳机，再做挂起测试。上游：[snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)。

## 命令速查

| 命令 | 作用 |
| --- | --- |
| `status` / `verify` / `verify-*` | 只读诊断 / 完整门禁 / 单阶段门禁 |
| `install-base` | 安装依赖并检查匹配内核 headers |
| `install-touchbar` | 安装固定版本 T1/Touch Bar DKMS 与服务 |
| `install-suspend` | 安装最小 PCIe/NVMe 配置 |
| `cleanup-legacy-all [--dry-run]` | 预览/清理旧版显示及强制休眠/IOMMU 覆盖 |
| `gpu-igpu --yes` | 门禁通过后开始带自动 AMD 回退的首次 Intel 启动 |
| `gpu-confirm-igpu --yes` | 确认当前 Intel 会话正常并取消自动 AMD 回退 |
| `gpu-dgpu --yes` | 设置下一启动为 AMD 偏好 |
| `install-wifi <MAC>` | 安装经过 SHA-256 校验的 BCM43602 NVRAM |
| `install-cooling` | CPU 省电/降温，不改显示 |
| `install-mbpfan` | 可选主动风扇服务 |
| `pm-test --yes` | 有条件的设备级挂起测试 |
| `install-audio --ack-kernel-risk` | 最后安装的可选音频 DKMS |
| `previous-boot` | 查看上一启动周期挂起/恢复日志 |
| `rollback` | 恢复备份、EFI 偏好并移除脚本服务/DKMS |

## 回滚

```bash
sudo ./omarchy-mbp15-2016.sh rollback
sudo reboot
```

回滚会禁用脚本服务、移除两个 DKMS 模块、恢复已备份的配置/Wi-Fi/mbpfan 二进制和 EFI GPU 变量，并刷新 Limine。若 `limine-update` 失败，脚本会明确警告；修复启动项之前不要重启。

## 固定的上游版本

提交号和 Wi-Fi SHA-256 直接记录在脚本顶部，更新时必须重新审计并修改：

- [nohzafk/omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1)
- [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)
- [linux-on-mac/mbpfan](https://github.com/linux-on-mac/mbpfan)

## 许可证

[MIT](LICENSE)
