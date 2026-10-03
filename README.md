# archsetup

适用于**刚用 live CD 装好 base 系统的 Arch Linux**：重启进入新系统、以 root 登录 tty 后，一条命令把它配置成可用的桌面。

```bash
curl -fsSL https://raw.githubusercontent.com/tyLingyu/archsetup/main/bootstrap.sh | bash
```

如果直连 GitHub 较慢：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/tyLingyu/archsetup/main/bootstrap.sh | bash
```

## 流程

1. **bootstrap.sh**（纯 bash）：检查环境 → 选择语言（中文会安装 `noto-fonts-cjk` 和 `kmscon`，并在 kmscon 里运行后续步骤）→ 对 GitHub 和各 gh-proxy 镜像测 ping，可选做真实 clone 测速 → clone 仓库 → 启动 `install.sh`
2. **install.sh**（dialog TUI）：一开始一次性问完所有问题（每一步都可以返回上一步），之后全自动运行：

| 模块 | 内容 |
|---|---|
| 00-presnap | 根分区为 btrfs 时，在安装任何包之前先打一个快照 |
| 10-mirrors | reflector |
| 11-repos | multilib、archlinuxcn、可选 chaotic-aur、paru；选了 gh-proxy 时，makepkg/git 下载 GitHub 也走代理 |
| 12-snapper | 配置 snapper，并把 00 的快照导入为 snapper 快照 |
| 20-base | 时区、locale、主机名、root/用户密码、sudo、微码 |
| 30-network | NetworkManager / NM+iwd / systemd-networkd（检测到已有配置时可以保留） |
| 40-bootloader | 保留现有，或安装 systemd-boot / GRUB / Limine / rEFInd；自动添加 Windows 启动项；btrfs 下支持从快照启动 |
| 50-gpu | Intel / AMD / NVIDIA（nvidia-open-dkms）/ 虚拟机 |
| 55-snapshot | 安装桌面之前再打一个快照 |
| 60-desktop | GNOME、KDE、DMS、Noctalia、Caelestia、end-4、tyLingyu/end4-dots，以及登录管理器 |
| 70-apps | 向导里按分类勾选的软件 |
| 99-finish | snap-pac，清理临时状态 |

进度保存在 `/var/lib/archsetup/`，日志在 `/var/log/archsetup.log`。中途失败时可以选择重试、跳过或中止；重新运行 `install.sh` 会从中断处继续。

## 自定义

- 软件清单：`lib/apps.sh`
- 界面文字：`lib/i18n.sh`

## 测试（QEMU）

需要 KVM、`qemu-system-x86` 和 `edk2-ovmf`，不需要 root。

```bash
test/vm.sh fetch                      # 下载并校验最新 ISO
test/vm.sh create systemd-boot        # 自动 pacstrap 一个全新的 btrfs 系统
test/vm.sh save fresh                 # 保存快照（reflink），之后可以反复 restore
test/vm.sh boot                       # UEFI 启动，ssh 端口 localhost:2222
test/vm.sh run minimal.conf           # 部署当前工作区并无人值守运行（test/answers/）
test/vm.sh ssh 'snapper list; efibootmgr'
test/vm.sh stop && test/vm.sh restore fresh
```

`install.sh` 无人值守运行：`ARCHSETUP_ANSWERS=<预设文件>`；`bootstrap.sh`：`ARCHSETUP_LANG=en|zh ARCHSETUP_SOURCE=<序号>`。
