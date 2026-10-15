中文：[README.md](README.md)

# No Sleep

While an app on the list is still running, this computer stays awake. It is meant for local agents such as Cursor, Claude Code, and Codex.

## Install

### macOS

1. Download [不许睡-mac.zip](不许睡-mac.zip).
2. Unzip it, then drag 不许睡.app into Applications.
3. The first time, Control-click the icon and choose Open.

It runs on both Intel and Apple silicon. Keeping the machine awake with the lid closed is offered only on Intel laptops.

### Windows

1. Download [不许睡.exe](不许睡.exe).
2. Double-click it. If lid sleep is checked, Save asks for administrator approval.

## How to use

1. Click an app on the left to add it. Click it on the right to remove it.
2. On an Intel laptop, check “Mind the lid and the battery” to stay awake with the lid closed.
3. The battery floor defaults to 20. Below that, on battery only, sleep is allowed. Plugged-in power ignores the floor.
4. Click Save. The window minimizes, and the app stays in the menu bar or system tray.
5. Reset clears the list and turns sleep prevention back to the normal, sleep-allowed state.

Closing the window does not quit. Choose Quit from the menu-bar or tray icon.

The menu also has Stay awake, which holds the lock even with an empty list, and Allow sleep, which pauses and wins over everything else.

## How it works

Sleep stops the CPU, so local programs stop with it. No Sleep prevents sleep. It does not keep programs running after the computer has already gone to sleep.

The lock is held while a listed app is running, or while Stay awake is on. The screen can still turn off. When those apps quit and Stay awake is off, the lock is released and the computer follows its own sleep settings.

The lock covers the whole computer. The list only decides when to hold it. No Sleep stays running in the background and does not hold the lock just because it is open.

The lid is separate. macOS changes the system sleep switch, and Windows changes what closing the lid does, so Save may ask for an administrator password. This is offered only on Intel laptops. Apple silicon lid behavior has not been verified, and desktops have no lid, so those machines do not show the option. If the system was already set to stay awake, the app leaves that setting alone when it quits. Reset is the action that puts sleep back to the normal, sleep-allowed state.
