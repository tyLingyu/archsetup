#!/usr/bin/env bash
# UI strings. Values are printf formats: use %s for arguments, %% for a literal %.
# A key missing in L_zh falls back to L_en.

L_en=(
    [backtitle]="archsetup — Arch Linux post-install setup"
    [ok]="OK" [back]="Back" [yes]="Yes" [no]="No" [start]="Start"
    [none]="none" [new]="new" [detected]="detected" [recommended]="recommended"
    [retry]="Retry" [skip]="Skip this module" [abort]="Abort"

    [pass_enter]="Enter password:"
    [pass_again]="Enter the password again:"
    [pass_empty]="Password must not be empty."
    [pass_mismatch]="Passwords do not match."

    [desk_title]="Desktop"
    [desk_text]="Choose a desktop. Everything after this wizard runs unattended.\n\nQuickshell shells install their compositor automatically."
    [desk_minimal]="Minimal — no desktop, base system only"
    [comp_title]="Compositor"
    [comp_text]="%s supports both niri and Hyprland. Which one?"
    [comp_niri]="scrollable tiling"
    [comp_hypr]="dynamic tiling, eye candy"

    [dm_title]="Login manager"
    [dm_text]="How do you want to log in?"
    [dm_none]="none — log in on the tty and start the compositor by hand"

    [chaotic_text]="chaotic-aur is not configured.\n\nUse chaotic-aur to install prebuilt AUR binaries instead of compiling them? Packages not in any repo will still be built with paru."

    [tz_title]="Timezone"
    [tz_text]="Current: %s\n\nRegion/City, e.g. Asia/Shanghai, Europe/Berlin, UTC"
    [tz_invalid]="Unknown timezone: %s"

    [loc_title]="System locale"
    [loc_text]="Current LANG: %s\n\nen_US.UTF-8 and zh_CN.UTF-8 are always generated."
    [loc_en]="English"
    [loc_enzh]="English system + Chinese desktop session (tty can't show CJK)"
    [loc_zh]="Simplified Chinese everywhere"

    [host_title]="Hostname"
    [host_text]="Current: %s"
    [host_invalid]="Letters, digits and '-' only, max 63 characters."

    [root_title]="Root password"
    [root_isset]="A root password is already set.\n\nChange it?"

    [user_title]="User"
    [user_existing]="existing user"
    [user_new]="create a new user"
    [user_pick]="Which user will use the desktop? (added to wheel / sudo)"
    [user_name]="New username:"
    [user_invalid]="Lowercase letters, digits, '_' and '-', starting with a letter."
    [user_exists]="User %s already exists."
    [user_pass_title]="Password for %s"
    [user_chpass]="%s already has a password.\n\nChange it?"

    [net_title]="Network"
    [net_found]="Enabled network services: %s\n\nReplace them?"
    [net_pick]="Choose the network stack (conflicting services will be disabled):"

    [boot_title]="Bootloader"
    [boot_found]="Detected bootloader: %s\n\nKeep it, or install a different one?"
    [boot_keep]="Keep %s"
    [boot_none]="No bootloader detected. Choose one to install:"
    [boot_bios]="(Legacy BIOS boot: only GRUB is available.)"
    [boot_cmdline]="Kernel cmdline (from the running system):\n  %s"
    [boot_rm_old]="Remove the old bootloader(s): %s ?\n\nFiles on the ESP, UEFI boot entries and packages are removed after %s is installed successfully. Choose No to keep them as a fallback."

    [apps_title]="Applications"
    [cat_fonts]="Fonts"
    [cat_input]="Input methods"
    [cat_browser]="Web browsers"
    [cat_terminal]="Terminal emulators (the desktop already ships one)"
    [cat_cli]="Command line tools"
    [cat_dev]="Development"
    [cat_media]="Multimedia & graphics"
    [cat_chat]="Chat & mail"
    [cat_office]="Office & notes"
    [cat_gaming]="Gaming"
    [cat_system]="System & utilities"

    [sum_title]="Summary"
    [sum_desktop]="Desktop" [sum_tz]="Timezone" [sum_host]="Hostname" [sum_user]="User"
    [sum_net]="Network" [sum_boot]="Bootloader" [sum_apps]="Apps"
    [sum_rm_old]="remove old" [sum_snap]="btrfs: snapper snapshots before the first package and before the desktop"
    [sum_confirm]="Start the installation? It runs unattended from here."

    [quit_title]="Quit"
    [quit_text]="Quit the installer?"

    [resume_title]="Previous run found"
    [resume_text]="Answers from a previous run were found."
    [resume]="Resume where it stopped"
    [restart]="Start over (ask everything again)"

    [done_title]="Done"
    [done_text]="Installation finished. Log in as %s after rebooting.\n\nFull log: %s"
    [done_failed]="These packages could not be installed: %s"
    [done_proxy]="GitHub downloads in makepkg/git still go through %s.\nRemove /etc/makepkg.conf.d/archsetup-ghproxy.conf and the url.*.insteadOf entry in /etc/gitconfig to undo."
    [done_reboot]="Reboot now?"

    [mod_failed]="Module %s failed (exit %s)."
    [mod_failed_title]="Error"
    [mod_failed_text]="Module %s failed.\n\nSee the output above and %s."
)

L_zh=(
    [backtitle]="archsetup — Arch Linux 安装后配置"
    [ok]="确定" [back]="返回" [yes]="是" [no]="否" [start]="开始"
    [none]="无" [new]="新建" [detected]="已检测到" [recommended]="推荐"
    [retry]="重试" [skip]="跳过此模块" [abort]="中止"

    [pass_enter]="输入密码："
    [pass_again]="再次输入密码："
    [pass_empty]="密码不能为空。"
    [pass_mismatch]="两次输入的密码不一致。"

    [desk_title]="桌面"
    [desk_text]="选择桌面。此向导结束后将全自动安装。\n\nQuickshell 类会自动安装所需的合成器。"
    [desk_minimal]="Minimal — 不装桌面，只配置基础系统"
    [comp_title]="合成器"
    [comp_text]="%s 同时支持 niri 和 Hyprland，选择哪个？"
    [comp_niri]="滚动式平铺"
    [comp_hypr]="动态平铺，特效丰富"

    [dm_title]="登录管理器"
    [dm_text]="选择登录方式："
    [dm_none]="不使用 — 在 tty 登录后手动启动合成器"

    [chaotic_text]="未配置 chaotic-aur。\n\n是否使用 chaotic-aur 直接安装预编译的 AUR 包，而不是本地编译？不在任何仓库中的包仍会用 paru 编译。"

    [tz_title]="时区"
    [tz_text]="当前：%s\n\n格式 地区/城市，例如 Asia/Shanghai、Europe/Berlin、UTC"
    [tz_invalid]="未知时区：%s"

    [loc_title]="系统语言"
    [loc_text]="当前 LANG：%s\n\nen_US.UTF-8 和 zh_CN.UTF-8 都会生成。"
    [loc_en]="英文"
    [loc_enzh]="系统英文 + 桌面中文（推荐：tty 无法显示中文）"
    [loc_zh]="全部简体中文"

    [host_title]="主机名"
    [host_text]="当前：%s"
    [host_invalid]="只能包含字母、数字和 '-'，最长 63 个字符。"

    [root_title]="root 密码"
    [root_isset]="root 已设置密码。\n\n是否修改？"

    [user_title]="用户"
    [user_existing]="已有用户"
    [user_new]="新建用户"
    [user_pick]="选择使用桌面的用户（会加入 wheel / sudo）："
    [user_name]="新用户名："
    [user_invalid]="只能包含小写字母、数字、'_' 和 '-'，并以字母开头。"
    [user_exists]="用户 %s 已存在。"
    [user_pass_title]="%s 的密码"
    [user_chpass]="%s 已设置密码。\n\n是否修改？"

    [net_title]="网络"
    [net_found]="已启用的网络服务：%s\n\n是否替换？"
    [net_pick]="选择网络管理方案（冲突的服务会被禁用）："

    [boot_title]="引导程序"
    [boot_found]="检测到引导程序：%s\n\n保留，还是安装其他引导程序？"
    [boot_keep]="保留 %s"
    [boot_none]="未检测到引导程序，请选择要安装的："
    [boot_bios]="（Legacy BIOS 启动：只能使用 GRUB。）"
    [boot_cmdline]="内核参数（取自当前系统）：\n  %s"
    [boot_rm_old]="是否删除旧的引导程序：%s ？\n\n会在 %s 安装成功后删除 ESP 中的文件、UEFI 启动项和对应的包。选“否”则保留作为备用。"

    [apps_title]="应用程序"
    [cat_fonts]="字体"
    [cat_input]="输入法"
    [cat_browser]="浏览器"
    [cat_terminal]="终端模拟器（桌面本身已自带一个）"
    [cat_cli]="命令行工具"
    [cat_dev]="开发"
    [cat_media]="影音与图形"
    [cat_chat]="聊天与邮件"
    [cat_office]="办公与笔记"
    [cat_gaming]="游戏"
    [cat_system]="系统与工具"

    [sum_title]="确认"
    [sum_desktop]="桌面" [sum_tz]="时区" [sum_host]="主机名" [sum_user]="用户"
    [sum_net]="网络" [sum_boot]="引导" [sum_apps]="软件"
    [sum_rm_old]="删除旧引导" [sum_snap]="btrfs：安装第一个包之前、安装桌面之前各打一个 snapper 快照"
    [sum_confirm]="开始安装？之后将全自动进行。"

    [quit_title]="退出"
    [quit_text]="退出安装程序？"

    [resume_title]="发现上次的进度"
    [resume_text]="找到了上次运行保存的选项。"
    [resume]="从中断处继续"
    [restart]="重新开始（重新回答所有问题）"

    [done_title]="完成"
    [done_text]="安装完成。重启后用 %s 登录。\n\n完整日志：%s"
    [done_failed]="以下软件包安装失败：%s"
    [done_proxy]="makepkg/git 下载 GitHub 仍会经过 %s。\n如需取消，删除 /etc/makepkg.conf.d/archsetup-ghproxy.conf 以及 /etc/gitconfig 中的 url.*.insteadOf。"
    [done_reboot]="现在重启？"

    [mod_failed]="模块 %s 失败（退出码 %s）。"
    [mod_failed_title]="错误"
    [mod_failed_text]="模块 %s 执行失败。\n\n请查看上方输出和 %s。"
)
