# omarchy-mbp15-2016

[English](README.md) | **简体中文**

面向 MacBook Pro 15 英寸（2016 款，`MacBookPro13,3`，配备 Touch Bar 与 T1 芯片）的 Omarchy / Arch Linux 硬件配置与诊断工具。

---

## 1. 双系统准备与说明

在开始安装前，请注意以下关键准备工作：

- **必须保留双系统与 macOS 分区**：请勿全盘抹除。必须保留原装 macOS、Apple EFI 和恢复环境（Recovery）。完全抹除 macOS/T1 固件会导致 Touch Bar 失去固件支持并陷入 `05ac:1281` DFU 恢复模式。
- **获取真实 Wi-Fi MAC 地址**：在 macOS 系统的终端中执行以下命令并记录输出：
  ```bash
  networksetup -getmacaddress en0
  ```
  安装 BCM43602 Wi-Fi NVRAM 配置时必须填入该真实 MAC 地址进行校准，请勿使用虚拟或临时 MAC。
- **保持系统与内核同步**：在全新安装后，建议先执行完整更新（`sudo pacman -Syu`）并重启，确保当前运行的内核与软件源版本一致（避免因单独执行 `pacman -Sy` 导致内核头文件版本错位）。脚本安装时会立即开启 CPU 降温防死机，并自动适配当前内核（如 `linux` 或 `linux-omarchy`）安装对应的 headers。
- **硬件支持范围**：脚本支持 Apple Radeon Pro 450 / 455 / 460（`1002:67ef`，子系统 `106b:0167/0166/0160`）。
- **清理遗留配置（可选）**：如果当前系统此前运行过旧版本脚本，建议在安装前清理遗留配置：
  ```bash
  sudo ./omarchy-mbp15-2016.sh cleanup-legacy-all
  ```

---

## 2. 默认一键安装

赋予脚本执行权限后，只需运行一条安装命令：

```bash
chmod +x omarchy-mbp15-2016.sh
sudo ./omarchy-mbp15-2016.sh install --wifi-mac AA:BB:CC:DD:EE:FF
```

> **提示**：如果此前已正确安装并校准过 Wi-Fi NVRAM，可使用 `--skip-wifi-nvram` 参数跳过：
> ```bash
> sudo ./omarchy-mbp15-2016.sh install --skip-wifi-nvram
> ```

该命令会自动完成推荐的稳定硬件配置：
1. **基础依赖**：自动安装编译依赖并核对当前内核精确 headers。
2. **Wi-Fi 网络**：使用填入的真实 MAC 安装并校准 BCM43602 NVRAM。
3. **散热与温控**：配置 CPU 节能温控策略，并编译安装运行 `mbpfan` 风扇守护进程。
4. **Touch Bar**：编译安装 T1/Touch Bar DKMS 驱动与自动加载服务。
5. **声卡音频**：编译安装内置声卡音频 DKMS 驱动（`snd_hda_macbookpro`）。

默认配置保持 **AMD 独显** 运行（内置音频工作正常、内屏与外接显示器均可用），并且默认不开启、不修改 iGPU 和睡眠挂起（suspend），以保证开箱即用的稳定性。

### 重启并验证

安装完成后重启系统，并执行验证命令：

```bash
sudo reboot
# 重启进入系统后执行：
sudo ./omarchy-mbp15-2016.sh verify
```

`verify` 会统一检查所有已安装的硬件模块及服务状态。测试扬声器、耳机、麦克风和 Touch Bar 正常后，即可投入日常使用。

---

## 3. 独立配置：切换 iGPU（核显模式）

默认情况下系统运行在 AMD 独显模式（发热与功耗相对较高，但支持外接显示器）。切换至 Intel 核显可显著降低日常运行发热并延长电池续航。

> **注意**：本机所有 USB-C 视频输出硬件直连在 AMD 独显上。**在核显模式下，外接显示器无法工作**。切换前请务必拔掉所有外接显示器与扩展坞。

### 步骤 1：直接检查核显是否就绪
在终端执行硬件检查命令：
```bash
lspci -nnk -s 00:02.0
```
如果输出显示 Intel 显卡且包含 `Kernel driver in use: i915`，说明核显已暴露并由内核接管，**可直接进入步骤 2**。

> **疑难排查**：若该命令没有任何输出，说明当前主板固件隐藏了核显。此时才需要在引导器中添加 `apple_set_os` 支持（例如让引导器启动前执行 `apple_set_os.efi` 伪装系统为 macOS）。

### 步骤 2：切换为核显并重启
确认已拔掉所有外接屏幕后，执行切换：
```bash
sudo ./omarchy-mbp15-2016.sh gpu-igpu --yes
sudo reboot
```
> **自动回退保护**：为防止内屏黑屏无法进入系统，脚本在首次切换 iGPU 时会自动装载保护——如果在本次启动中未人工确认，下一次重启将自动恢复为 AMD 独显。

### 步骤 3：验证并确认永久保留核显
重启进入桌面后，确认内屏显示、键盘、触控板等一切正常，执行以下命令验证并**永久保留**核显设置：
```bash
sudo ./omarchy-mbp15-2016.sh verify-gpu
sudo ./omarchy-mbp15-2016.sh gpu-confirm-igpu --yes
```
执行确认后，核显配置长期生效。

---

### （可选）何时以及如何切回 AMD 独显？

> **重要警告**：以下命令仅在**你需要切回独显时**才执行（例如需要连接外接显示器、运行高负载图形任务，或者核显出现异常时）。**请勿在刚刚配置好核显后顺手执行，否则会直接将设置恢复回独显！**

若需恢复为 AMD 独显，运行：
```bash
sudo ./omarchy-mbp15-2016.sh gpu-dgpu --yes
sudo reboot
```
重启后系统将重新以 AMD Radeon Pro 独显运行。

---

## 4. 独立配置：挂起与睡眠（Suspend）

由于苹果硬件与电源管理架构的特殊性，睡眠挂起在此机型上属于实验性功能。建议在 iGPU 模式稳定工作后再进行配置。

### 步骤 1：安装挂起配置
```bash
sudo ./omarchy-mbp15-2016.sh install-suspend
sudo reboot
```
该命令会写入 `pcie_ports=compat` 内核启动参数，并启用针对本机 NVMe 控制器的 D3cold 修复服务，防止唤醒后硬盘掉盘或 USB-C 控制器异常。

### 步骤 2：验证挂起配置
重启后执行：
```bash
sudo ./omarchy-mbp15-2016.sh verify-suspend
```

### 步骤 3：测试挂起
先通过设备级挂起测试验证硬件能否正常恢复：
```bash
sudo ./omarchy-mbp15-2016.sh pm-test --yes
```
测试通过后，保存好当前正在编辑的工作文件，在机身前手动触发真实睡眠挂起：
```bash
sudo systemctl suspend
```
合盖或按键唤醒，测试系统和外设是否正常恢复。

---

## 5. 故障排查与一键回滚

### 启动异常排查
若遇到黑屏、死机或唤醒失败，进入系统（或通过 AMD/macOS 恢复入口进入）后，先保存上一次启动周期的内核与挂起日志：
```bash
sudo ./omarchy-mbp15-2016.sh previous-boot
sudo journalctl -b -1 -k
```

### 一键回滚
如需卸载配置并恢复至脚本执行前的状态：
```bash
sudo ./omarchy-mbp15-2016.sh rollback
sudo reboot
```
回滚会还原原始 EFI GPU 偏好、卸载 T1 与音频 DKMS 模块、停用脚本相关 systemd 服务，并恢复系统原始配置和引导项。

---

## 6. 常用命令速查

| 命令 | 说明 |
| :--- | :--- |
| `status` | 查看当前硬件识别、驱动加载与内核参数状态 |
| `install --wifi-mac <MAC>` | 一键安装推荐的完整硬件配置（不含 iGPU / 挂起） |
| `install --skip-wifi-nvram` | 一键安装完整硬件配置（跳过 Wi-Fi NVRAM 写入） |
| `verify` | 统一验证默认安装的各个硬件模块与服务运行状态 |
| `cleanup-legacy-all [--dry-run]` | 检查 / 清除旧版脚本遗留的显示与休眠配置 |
| `gpu-igpu --yes` | 切换下次启动为 Intel 核显（带单次启动回退保护） |
| `gpu-confirm-igpu --yes` | 确认当前 Intel 核显正常并永久保留 |
| `gpu-dgpu --yes` | 切换下次启动为 AMD 独显 |
| `verify-gpu` | 检查当前活动显卡与下次启动 EFI 设置 |
| `install-suspend` | 安装睡眠挂起相关内核参数与 NVMe D3cold 修复服务 |
| `verify-suspend` | 验证挂起与 NVMe 配置生效情况 |
| `pm-test --yes` | 执行设备级挂起与唤醒测试 |
| `previous-boot` | 抓取上一启动周期的内核休眠/唤醒与报错日志 |
| `rollback` | 完整回滚脚本修改并恢复原始系统状态 |

---

## 上游项目与鸣谢

- T1 / Touch Bar 驱动：[nohzafk/omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1)
- 内置音频驱动：[davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)
- 风扇温控守护：[linux-on-mac/mbpfan](https://github.com/linux-on-mac/mbpfan)
- EFI 显卡切换原理：[0xbb/gpu-switch](https://github.com/0xbb/gpu-switch)
- 硬件参考文档：[Dunedan/mbp-2016-linux](https://github.com/Dunedan/mbp-2016-linux)

## 许可证

[MIT](LICENSE)
