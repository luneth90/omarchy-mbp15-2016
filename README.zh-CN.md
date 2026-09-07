# omarchy-mbp15-2016

[English](README.md) | **简体中文**

面向 `MacBookPro13,3`（15 英寸，2016，Touch Bar/T1）的 Omarchy/Arch 硬件安装与诊断脚本。

当前代码审查与自动测试并不是目标机器上的实机认证：固定的 T1 配方上游报告是在另一款 T1 Mac 上验证，`MacBookPro13,3` 仍必须按下述阶段逐项实测。脚本把 DKMS 安装限制在已审查的 Linux `7.1.x/7.2.x` 范围，超出后应先重新审计，而不是强行安装。

## 先读：iGPU 不是普通的一键切换

在 `MacBookPro13,3` 上，从非 macOS 引导时固件通常只暴露 AMD 独显。仅写入 `gpu-power-prefs`，却没有让引导器执行 `apple_set_os`，可能导致 Intel 核显不可用、内屏黑屏。外接 USB-C 视频输出通常又连接到 AMD 独显，因此 iGPU 模式下不能把外接屏当作救援显示器。

本版脚本因此做了这些限制：

- 默认 `install` 一次完成全部必要硬件组件，但明确不包含 iGPU 切换和挂起配置。
- GPU 命令只接受 Apple Radeon Pro 450/455/460（`1002:67ef`，子系统 `106b:0167/0166/0160`），其他硬件直接拒绝。
- `gpu-igpu` 只有在 `00:02.0` 已可见、已绑定 `i915`、没有外接屏、没有旧版显示或强制休眠/IOMMU 配置时才允许执行。
- GPU 命令只设置下一次启动的 EFI 偏好；不会热切换显卡，不会写 `AQ_DRM_DEVICES`，不会猜测 `card0/card1` 或 `eDP-1/eDP-2`。
- 第一次 iGPU 启动默认把再下一次启动预设回 AMD；只有桌面验证成功并执行 `gpu-confirm-igpu --yes` 后才永久保留 Intel 偏好。
- 首次更改 EFI 前保存原值；`rollback` 会恢复原值。
- GPU 更改和实际挂起测试都要求显式 `--yes`。

上游硬件说明：[Dunedan/mbp-2016-linux](https://github.com/Dunedan/mbp-2016-linux)。EFI 切换原理参考：[0xbb/gpu-switch](https://github.com/0xbb/gpu-switch)。

> 必须保留 macOS、Apple EFI 和恢复环境。脚本不会分区，但抹除 macOS/T1 固件环境可能使 Touch Bar 进入 `05ac:1281` DFU 状态。

## 可靠安装顺序

推荐的日常使用基线是保持 AMD 独显，并安装可用的内置音频。iGPU 切换和挂起是两个独立实验，不属于默认安装路径。每个阶段完成后先验证，再进行下一阶段；不要在无人值守或无法物理接触机器时测试重启或挂起。

### 0. 固定测试环境并准备恢复路径

全新部署目标机器时优先使用 Omarchy `stable`，运行此脚本不要求 `edge`。如果机器已经在可正常工作的 `edge` 上，不要仅为了脚本切换 channel。先记录精确环境；整个分阶段验收期间不要更新 Omarchy/内核、切换 channel 或拉取新版脚本：

```bash
omarchy channel current
omarchy version
uname -r
git rev-parse HEAD
```

然后完成以下准备：

1. 确认 macOS、Apple EFI 和 Recovery 仍可启动。
2. 确认启动菜单中存在已知可用的 AMD 或旧内核恢复入口。
3. 保存工作，拔掉所有 USB-C 显示器、扩展坞和非必要外设。
4. 在 macOS 记录真实 Wi-Fi MAC：`networksetup -getmacaddress en0`。

### 1. 核对受支持显卡并首先清理旧配置

```bash
chmod +x omarchy-mbp15-2016.sh
sudo ./omarchy-mbp15-2016.sh status
lspci -nnv -s 01:00.0
sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all --dry-run
```

PCI 输出必须符合以下任一受支持的 Apple 显卡身份：

- Radeon Pro 460：`1002:67ef`，子系统 `106b:0160`
- Radeon Pro 455：`1002:67ef`，子系统 `106b:0166`
- Radeon Pro 450：`1002:67ef`，子系统 `106b:0167`

脚本会自动识别并显示实际型号，并非只对应 Pro 460。物理身份不在此列表时不要继续。如果 dry-run 确实报告旧版脚本遗留配置，必须在安装其他组件之前执行清理：

```bash
sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all
sudo reboot
sudo ./omarchy-mbp15-2016.sh status
```

全新系统没有遗留项时，不需要执行实际清理命令。

### 2. 一条命令完成默认安装

```bash
sudo ./omarchy-mbp15-2016.sh install --wifi-mac AA:BB:CC:DD:EE:FF
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify
```

这一条安装命令会自动完成默认配置：

- 基础依赖与当前运行内核的精确 headers
- 使用 macOS 真实 MAC 安装 BCM43602 Wi-Fi NVRAM
- CPU 降温策略与固定版本 `mbpfan`
- 固定版本 T1/Touch Bar DKMS 与服务
- 必需的固定版本音频 DKMS，并安排在最后安装

它不会修改 GPU 偏好，也不会安装挂起配置。必需音频驱动仍受已审查内核范围和精确 headers 两道硬门禁保护，不再要求额外确认参数。如果已经安装并验证过正确的 Wi-Fi NVRAM，可改用：

```bash
sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram
```

一次重启后，`verify` 会统一验证整个默认配置，并且不会把 suspend 当成必需项。随后测试扬声器、耳机、麦克风、再次重启以及正常负载；这就是推荐的默认完成点。各个 `install-*` 和 `verify-*` 命令继续保留给故障诊断和单组件重装，正常首次安装不需要逐项手动执行。

## 可选实验：iGPU

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

## 可选实验：挂起

不要提前安装挂起配置。只有上述 iGPU 会话已确认，并且经历多次正常启动之后，才能在现场且没有外接屏时继续：

```bash
sudo ./omarchy-mbp15-2016.sh install-suspend
sudo reboot
sudo ./omarchy-mbp15-2016.sh verify-suspend
sudo ./omarchy-mbp15-2016.sh pm-test --yes
```

`install-suspend` 只加入 `pcie_ports=compat`，并启用针对实际 NVMe PCI 地址的 D3cold 服务；不强制 `s2idle`、IOMMU，也不覆盖其他 Omarchy 服务。`pm-test` 使用 `pm_test=devices`，仍不等同于真实低功耗挂起。保存工作后再手动执行一次：

```bash
sudo systemctl suspend
```

## 黑屏、死机或启动失败后

不要立即重装系统并清除证据。通过 AMD 或恢复入口重新进入系统后，先保存上一启动周期日志：

```bash
sudo ./omarchy-mbp15-2016.sh previous-boot
sudo journalctl -b -1 -k
```

需要时再执行回滚：

```bash
sudo ./omarchy-mbp15-2016.sh rollback
sudo reboot
```

## 命令速查

| 命令 | 作用 |
| --- | --- |
| `status` / `verify` / `verify-*` | 只读诊断 / 默认配置统一门禁（不要求 suspend）/ 单阶段门禁 |
| `install --wifi-mac <MAC>` | 一次安装完整默认配置；不包含 iGPU 和 suspend |
| `install-base` | 仅安装依赖并检查匹配内核 headers，供维修使用 |
| `install-touchbar` | 安装固定版本 T1/Touch Bar DKMS 与服务 |
| `install-suspend` | 安装最小 PCIe/NVMe 配置 |
| `cleanup-legacy-all [--dry-run]` | 预览/清理旧版显示及强制休眠/IOMMU 覆盖 |
| `gpu-igpu --yes` | 门禁通过后开始带自动 AMD 回退的首次 Intel 启动 |
| `gpu-confirm-igpu --yes` | 确认当前 Intel 会话正常并取消自动 AMD 回退 |
| `gpu-dgpu --yes` | 设置下一启动为 AMD 偏好 |
| `install-wifi <MAC>` | 安装经过 SHA-256 校验的 BCM43602 NVRAM |
| `install-cooling` | CPU 省电/降温，不改显示 |
| `install-mbpfan` | 单独重装默认配置包含的主动风扇服务 |
| `pm-test --yes` | 有条件的设备级挂起测试 |
| `install-audio` | 单独重装默认配置中最后安装的必需音频 DKMS |
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
