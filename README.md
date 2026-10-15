# 不许睡 No Sleep

名单里的应用还在运行时，不让这台电脑休眠。适合 Cursor、Claude Code、Codex 这类要在本机持续干活的程序。

While an app on the list is still running, this computer stays awake. It is meant for local agents such as Cursor, Claude Code, and Codex.

## 安装 Install

### macOS

1. 下载 [不许睡-mac.zip](不许睡-mac.zip)。Download [不许睡-mac.zip](不许睡-mac.zip).
2. 解压，把「不许睡.app」拖进「应用程序」。Unzip it, then drag 不许睡.app into Applications.
3. 第一次打开：按住 Control 点应用图标，选择「打开」。The first time, Control-click the icon and choose Open.

Intel 和 Apple 芯片都可以用。合盖不休眠只出现在 Intel 笔记本上。

It runs on both Intel and Apple silicon. Keeping the machine awake with the lid closed is offered only on Intel laptops.

### Windows

1. 下载 [不许睡.exe](不许睡.exe)。Download [不许睡.exe](不许睡.exe).
2. 双击运行。勾了合盖再点保存时，会要求管理员确认。Double-click it. If lid sleep is checked, Save asks for administrator approval.

## 怎么用 How to use

1. 点左侧的应用，它会进入右侧「不许睡」名单。再点右侧的应用，会把它移出名单。Click an app on the left to add it. Click it on the right to remove it.
2. Intel 笔记本可以勾上「放心合盖，小心电量」。On an Intel laptop, check “Mind the lid and the battery” to stay awake with the lid closed.
3. 电池电量下限默认 20。只用电池并且低于这个数时，允许休眠。接上电源时不看这个数。The battery floor defaults to 20. Below that, on battery only, sleep is allowed. Plugged-in power ignores the floor.
4. 点「保存」。窗口会最小化，软件继续留在菜单栏或托盘。Click Save. The window minimizes, and the app stays in the menu bar or system tray.
5. 「恢复默认」会清空右侧名单，并把合盖和不休眠改回允许休眠。Reset clears the list and turns sleep prevention back to the normal, sleep-allowed state.

关掉窗口不会退出。从菜单栏或托盘图标里选「退出」。

Closing the window does not quit. Choose Quit from the menu-bar or tray icon.

菜单里还可以选「现在不许睡」（不看名单，一直握住）和「先允许睡」（暂停，并且优先于其他选项）。

The menu also has Stay awake, which holds the lock even with an empty list, and Allow sleep, which pauses and wins over everything else.

## 核心原理 How it works

电脑休眠后 CPU 会停，本机上的程序也会停。不许睡阻止的是休眠，它不能让程序在已经睡着的电脑里继续跑。

Sleep stops the CPU, so local programs stop with it. No Sleep prevents sleep. It does not keep programs running after the computer has already gone to sleep.

名单里有应用正在运行，或者手动选了「现在不许睡」时，软件握住整台电脑的空闲休眠锁。屏幕仍然可以自己关掉。名单里的应用都退出，也没有手动握住时，锁放开，电脑按系统自己的设置休眠。

The lock is held while a listed app is running, or while Stay awake is on. The screen can still turn off. When those apps quit and Stay awake is off, the lock is released and the computer follows its own sleep settings.

这把锁是整机的。名单只决定什么时候握住。不许睡自己一直开着，不会因此握住锁。

The lock covers the whole computer. The list only decides when to hold it. No Sleep stays running in the background and does not hold the lock just because it is open.

合盖是另一件事。macOS 上要改系统的休眠开关，Windows 上要改合盖按下后的动作，所以保存时可能要管理员密码。这项只在 Intel 笔记本上提供。Apple 芯片的合盖结果没有验证，台式机没有盖子，这两种机器都不显示这个选项。系统如果本来就已经不休眠，软件不会接管，退出时也不会把它改回去。「恢复默认」会明确把它改回允许休眠。

The lid is separate. macOS changes the system sleep switch, and Windows changes what closing the lid does, so Save may ask for an administrator password. This is offered only on Intel laptops. Apple silicon lid behavior has not been verified, and desktops have no lid, so those machines do not show the option. If the system was already set to stay awake, the app leaves that setting alone when it quits. Reset is the action that puts sleep back to the normal, sleep-allowed state.
