package main

func shouldHold(paused, manual bool, floor int, onBattery, percentKnown bool, percent int, selectedRunning bool) bool {
	if paused {
		return false
	}
	if onBattery && percentKnown && percent < floor {
		return false
	}
	return manual || selectedRunning
}

func describe(paused, manual, holding, selectedRunning, lidEnabled, lidOwned, systemAlreadyAwake bool, floor, percent int, onBattery, percentKnown bool, lidError string) string {
	if lidError != "" {
		return lidError
	}
	if paused {
		return tr("先允许睡", "Allow sleep")
	}
	if onBattery && percentKnown && percent < floor {
		return tr("电池低于下限，可以睡了", "Battery is below the floor. Sleep is allowed.")
	}
	prefix := tr("电源 · ", "Power · ")
	if onBattery && percentKnown {
		prefix = tr("电池 · ", "Battery · ")
	}
	if holding && manual && !selectedRunning {
		return prefix + tr("现在不许睡", "Stay awake")
	}
	if holding && selectedRunning {
		return prefix + tr("名单里的应用还在，不许睡", "A listed app is running")
	}
	if lidEnabled && systemAlreadyAwake && !lidOwned {
		return tr(
			"可以睡。系统合盖已经是不休眠，退出本应用不会改动它",
			"Sleep is allowed. Lid sleep was already off, and quitting will leave that alone.",
		)
	}
	return tr("可以睡", "Sleep is allowed")
}

var chineseUI bool

func tr(zh, en string) string {
	if chineseUI {
		return zh
	}
	return en
}
