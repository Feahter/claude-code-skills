---
name: night-run
description: macOS 长效防睡眠开关,让长任务不被系统睡眠冻结中断。当用户说"任务跑一会儿就断、别让它睡、保持唤醒、保持持续执行、防睡眠、长效/永久/一直保活、夜间或整夜跑、开启或关闭保活、night-run"时触发。开一次就一直保活到手动关闭(无时限,进程被杀自动拉起,重启后自动恢复),整机不空闲睡眠,任何会话的任务都免疫冻结、无需切换。不限于夜间。不适用:"关终端后任务还继续"(那要 tmux,见下)、Linux/Windows。
---

# night-run:macOS 长效防睡眠开关

## 它治什么、不治什么

macOS `pmset` 默认 `sleep 1`(空闲 1 分钟整机睡眠),睡眠冻结所有进程 —— 这是"任务跑一会儿就断"最常见的根因。本开关让 **launchd 常驻托管一条 `caffeinate -i`**(和会话解耦),开着期间整机不睡,**当前及任何会话的任务都免疫冻结,无需切到别处**。不限夜间,白天长任务同样用它。

开关是**长效**的,三层含义:不带 `-t` 所以没有到期时间(`pmset -g assertions` 里显示 `asserting forever`);`KeepAlive` 让进程被意外杀掉后 1 秒内自动拉起;plist 放在 `~/Library/LaunchAgents` 所以重启登录后自动恢复。关闭是 bootout 加删 plist 两步,删掉了才不会在下次登录自动回来 —— 因此「plist 是否在位」就是开关的持久状态,`status` 的"重启后"一行读的就是它。

它**不治**"关掉终端后任务还继续":关终端会 SIGHUP 掉那个会话的 claude 进程本身,这是 OS 行为,任何后台开关都救不回。真要关终端走人,得把跑任务的会话放进 `tmux`(off 提示里给了命令),二者正交,可叠加使用。

## 开关怎么用

**日常首选桌面开关,不用开会话**:双击 `~/Desktop/保持唤醒.app` 切换开/关。它只是壳,逻辑仍是下面的脚本。用户只是要开关保活时,提示他双击即可,别为此消耗一次会话。

**图标本身就是状态指示**:睁眼猫 = 保活开着,闭眼猫(右上角飘 z)= 已关闭。每次切换 `sync_icon` 把对应那只贴到 app 上,所以不点开、不看通知,扫一眼桌面就知道当前是开还是关 —— 通知只是切换那一刻的回显,一闪就没,不能当状态看。要一个确定答案就跑 `night-run.sh status`,它读 plist 和 launchd,是权威;图标是它的投影,只在走脚本切换时同步(手工 `launchctl bootout` 绕过脚本会让两者不一致)。

`~/.claude/scripts/night-run.sh`,四个子命令,都不再接时长参数:

```bash
~/.claude/scripts/night-run.sh on       # 开启:一直保活到手动关闭,重启后自动恢复
~/.claude/scripts/night-run.sh status   # 查看:开关状态 / 重启后是否恢复 / 电源
~/.claude/scripts/night-run.sh off      # 关闭:停进程 + 卸载常驻,重启后不再恢复
~/.claude/scripts/night-run.sh toggle   # 开着就关、关着就开;只打印一行摘要,给桌面开关用
```

开着就行,该在哪个会话跑任务就在哪跑,不用切换。只认自己那条 launchd 作业(label `com.keepawake.agent`),不误杀 claude 自带的短命 caffeinate —— 想分辨谁是谁,看 `pmset -g assertions`:本开关那条写 `asserting forever`,claude 自带的写 `asserting for 300 secs`。

## 改桌面开关 / 重装

改完 AppleScript 或图标网格,**跑一次安装脚本**,别手工 osacompile:

```bash
PREFIX=~/.claude/scripts bash ~/.claude/scripts/keepawake-install.sh
```

本机 `PREFIX` 必须显式给成 `~/.claude/scripts`(源就在那儿),否则会按默认装到 `~/.local/share/keepawake`,变成两份。SRC 与 PREFIX 相同时脚本会跳过复制,只重画图标、重编译 app、按当前真实状态贴图标并重签,幂等可反复跑。

为什么不手工编:**`osacompile` 会重写整个 bundle,包括 `applet.icns`**,手工编完图标就被打回 AppleScript 默认样子;而且 `.applescript` 源里的脚本路径和通知标题是 `__SCRIPT_PATH__` / `__TITLE__` 占位符,由安装脚本 sed 成实际安装路径 —— 直接编出来的 app 会去执行字面量 `__SCRIPT_PATH__`,一点就报错。安装脚本把这几步和重签排好了顺序(改 bundle 内容签名就失效,不重签下次可能起不来)。

图标是脚本画的像素猫,不是图片文件:`make-cat-icon.py` 用字符网格描点,`HALF_32` / `HALF_16` 只写左半边由脚本镜像(保证对称),`SLEEP_ROWS_*` 是闭眼那几行的覆盖,`Z_OVERLAY` 是右上角那个 z(不对称,单独盖)。要改样子就改网格,跑一次脚本,看 `/tmp/keepawake-cat-preview.png` 和 `-sleep-preview.png` 核对。三条约束别破:输出尺寸必须是网格边长的整数倍(否则像素画糊掉);16px 单独用 `HALF_16`,别拿 32 缩一半(1 格宽的胡须会被吃掉);不要试图在 32x32 右侧画尾巴(只剩 4 列,画出来是个带孔的环,已试过并否决)。

`sync_icon` 全程容错、只 `return 0`:图标是装饰,任何一步失败都不许影响保活本身。刷新缓存用 `lsregister -f`,**别改回 `osascript` 让 Finder update** —— 那个要「控制 Finder」授权,首次会弹框,用户不点就挂着一个 osascript 进程,每次切换再攒一个。若图标仍不刷新,`killall Dock`。

## 给别的机器用

`~/Desktop/keepawake-installer.tar.gz` 是可分发的安装包(11 KB,不含 icns,装时现画)。对方解包跑 `./keepawake-install.sh` 即可,不需要 sudo(装的是 per-user LaunchAgent)。`PREFIX` 换安装目录,`KEEPAWAKE_APP_NAME` 换桌面 app 名和通知标题。卸载跑安装目录里的 `keepawake-uninstall.sh`。

重新打包(改了任何源文件之后):

```bash
cd ~/.claude/scripts && D=$(mktemp -d)/keepawake && mkdir -p "$D" \
  && cp night-run.sh night-run-switch.applescript make-cat-icon.py \
        keepawake-install.sh keepawake-uninstall.sh keepawake-README.md "$D/" \
  && tar czf ~/Desktop/keepawake-installer.tar.gz -C "$(dirname "$D")" keepawake
```

包里那份 `keepawake-README.md` 是给外人看的完整说明(装、用、卸、改图标、资源占用),本 skill 是给自己看的操作手册,两者别互相复制正文。

写 shell 时注意一个坑:**变量紧跟中文字符必须写 `${VAR}`**。`"当前是「$STATE」"` 会让 bash 把中文字节吃进变量名,报 `STATE\xef: unbound variable`,而且只在那行真正执行时才炸(比如只在缺依赖分支里的提示语,平时测不出来)。

## 硬前提(必须提醒用户)

- **开盖 + 插电源**:MacBook 合盖是硬睡眠,`caffeinate -i` 顶不住;电池耗尽同样断。`on` 时脚本检测电池供电会提醒。
- 需要合盖也跑,得改 `pmset`(另一档改动,本 skill 不含)。

## 校验

改脚本后 `bash -n ~/.claude/scripts/night-run.sh` 自检,再按下面四项过一遍(改桌面开关只需最后一项):

```bash
night-run.sh on && night-run.sh status          # 状态、"重启后: 自动恢复"、电源
launchctl print gui/$(id -u)/com.keepawake.agent | grep -E "state|properties"
                                                # 应见 running 与 keepalive | runatload
pmset -g assertions | grep -A1 "$(...pid...)"   # 本开关那条应为 asserting forever
open -W ~/Desktop/保持唤醒.app && night-run.sh status   # 双向翻转且命令没被挂住
cmp -s ~/.claude/scripts/keepawake-cat-sleep.icns \
       ~/Desktop/保持唤醒.app/Contents/Resources/applet.icns   # 关状态下应相等
```

`status` 只读 plist 与 `launchctl list`,不代表系统真的收到断言 —— 判断"到底防没防住睡眠"要看 `pmset -g assertions`,这是唯一的系统侧证据。

无法在会话里实测的一项:**重启后自动恢复**。它依赖 `~/Library/LaunchAgents` 登录自动加载加 `RunAtLoad`,是 launchd 的标准契约,但本机未真重启验证过。哪天重启后想确认,登录后跑一次 `status` 看是不是"开"。
