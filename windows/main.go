//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"unsafe"
)

const (
	wmDestroy   = 0x0002
	wmSize      = 0x0005
	wmClose     = 0x0010
	wmSetFont   = 0x0030
	wmCommand   = 0x0111
	wmTimer     = 0x0113
	wmTray      = 0x8001
	wmLButtonUp = 0x0202
	wmRButtonUp = 0x0205

	wsOverlapped = 0x00CF0000
	wsChild      = 0x40000000
	wsVisible    = 0x10000000
	wsBorder     = 0x00800000
	wsVScroll    = 0x00200000
	wsTabStop    = 0x00010000
	lbsNotify    = 0x0001
	esCenter     = 0x0001
	esNumber     = 0x2000
	bsAutoCheck  = 0x0003
	bmSetCheck   = 0x00F1
	bstChecked   = 1
	lbAddString  = 0x0180
	lbReset      = 0x0184
	lbGetCurSel  = 0x0188
	swHide       = 0
	swShow       = 5
	swMinimize   = 6
	idLeft       = 101
	idRight      = 102
	idFloor      = 103
	idLid        = 104
	idSave       = 105
	idReset      = 107
	idStatus     = 106
	seeNoClose   = 0x00000040
	esContinuous = 0x80000000
	esSystem     = 0x00000001
	nimAdd       = 0x00000000
	nimDelete    = 0x00000002
	nifMessage   = 0x00000001
	nifIcon      = 0x00000002
	nifTip       = 0x00000004
	mfString     = 0x00000000
	tpmReturn    = 0x0100
	colorWindow  = 5
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	shell32   = syscall.NewLazyDLL("shell32.dll")
	gdi32     = syscall.NewLazyDLL("gdi32.dll")
	powrprof  = syscall.NewLazyDLL("powrprof.dll")

	pRegisterClass   = user32.NewProc("RegisterClassExW")
	pCreateWindow    = user32.NewProc("CreateWindowExW")
	pDefWindowProc   = user32.NewProc("DefWindowProcW")
	pShowWindow      = user32.NewProc("ShowWindow")
	pUpdateWindow    = user32.NewProc("UpdateWindow")
	pGetMessage      = user32.NewProc("GetMessageW")
	pTranslate       = user32.NewProc("TranslateMessage")
	pDispatch        = user32.NewProc("DispatchMessageW")
	pPostQuit        = user32.NewProc("PostQuitMessage")
	pSendMessage     = user32.NewProc("SendMessageW")
	pSetTimer        = user32.NewProc("SetTimer")
	pGetClientRect   = user32.NewProc("GetClientRect")
	pMoveWindow      = user32.NewProc("MoveWindow")
	pSetWindowText   = user32.NewProc("SetWindowTextW")
	pGetWindowText   = user32.NewProc("GetWindowTextW")
	pLoadCursor      = user32.NewProc("LoadCursorW")
	pLoadIcon        = user32.NewProc("LoadIconW")
	pMessageBox      = user32.NewProc("MessageBoxW")
	pEnumWindows     = user32.NewProc("EnumWindows")
	pIsWindowVisible = user32.NewProc("IsWindowVisible")
	pGetWindowTextLn = user32.NewProc("GetWindowTextLengthW")
	pGetWindowPID    = user32.NewProc("GetWindowThreadProcessId")
	pSetForeground   = user32.NewProc("SetForegroundWindow")
	pDestroyWindow   = user32.NewProc("DestroyWindow")
	pCreatePopup     = user32.NewProc("CreatePopupMenu")
	pAppendMenu      = user32.NewProc("AppendMenuW")
	pTrackPopup      = user32.NewProc("TrackPopupMenu")
	pGetCursorPos    = user32.NewProc("GetCursorPos")
	pDestroyMenu     = user32.NewProc("DestroyMenu")

	pGetModule    = kernel32.NewProc("GetModuleHandleW")
	pSetExecState = kernel32.NewProc("SetThreadExecutionState")
	pSnapshot     = kernel32.NewProc("CreateToolhelp32Snapshot")
	pProcessFirst = kernel32.NewProc("Process32FirstW")
	pProcessNext  = kernel32.NewProc("Process32NextW")
	pOpenProcess  = kernel32.NewProc("OpenProcess")
	pCloseHandle  = kernel32.NewProc("CloseHandle")
	pQueryImage   = kernel32.NewProc("QueryFullProcessImageNameW")
	pPowerStatus  = kernel32.NewProc("GetSystemPowerStatus")
	pWait         = kernel32.NewProc("WaitForSingleObject")
	pExitCode     = kernel32.NewProc("GetExitCodeProcess")
	pCurrentPID   = kernel32.NewProc("GetCurrentProcessId")

	pShellExec  = shell32.NewProc("ShellExecuteExW")
	pNotifyIcon = shell32.NewProc("Shell_NotifyIconW")
	pCreateFont = gdi32.NewProc("CreateFontW")
)

type wndClass struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   uintptr
	Icon       uintptr
	Cursor     uintptr
	Background uintptr
	MenuName   *uint16
	ClassName  *uint16
	IconSm     uintptr
}

type point struct{ X, Y int32 }

type msg struct {
	Hwnd    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      point
}

type rect struct{ Left, Top, Right, Bottom int32 }

type processEntry struct {
	Size            uint32
	Usage           uint32
	ProcessID       uint32
	DefaultHeapID   uintptr
	ModuleID        uint32
	Threads         uint32
	ParentProcessID uint32
	PriClassBase    int32
	Flags           uint32
	ExeFile         [260]uint16
}

type shellExecInfo struct {
	CbSize     uint32
	FMask      uint32
	Hwnd       uintptr
	Verb       *uint16
	File       *uint16
	Parameters *uint16
	Directory  *uint16
	Show       int32
	InstApp    uintptr
	IDList     uintptr
	Class      *uint16
	Key        uintptr
	HotKey     uint32
	Icon       uintptr
	Process    uintptr
}

type notifyIcon struct {
	CbSize   uint32
	Hwnd     uintptr
	UID      uint32
	Flags    uint32
	Callback uint32
	Icon     uintptr
	Tip      [128]uint16
}

type systemPower struct {
	ACLineStatus        byte
	BatteryFlag         byte
	BatteryLifePercent  byte
	SystemStatusFlag    byte
	BatteryLifeTime     uint32
	BatteryFullLifeTime uint32
}

type appItem struct {
	Name string `json:"name"`
	Path string `json:"path"`
}

type lidRestore struct {
	AC     int  `json:"ac"`
	DC     int  `json:"dc"`
	Active bool `json:"active"`
}

type appConfig struct {
	Apps         []appItem   `json:"apps"`
	BatteryFloor int         `json:"batteryFloor"`
	LidEnabled   bool        `json:"lidEnabled"`
	Paused       bool        `json:"paused"`
	Manual       bool        `json:"manual"`
	LidRestore   *lidRestore `json:"lidRestore,omitempty"`
}

var (
	mainWindow   uintptr
	statusText   uintptr
	leftList     uintptr
	rightList    uintptr
	floorEdit    uintptr
	lidCheck     uintptr
	resetButton  uintptr
	saveButton   uintptr
	uiFont       uintptr
	config       appConfig
	catalog      []appItem
	holding      bool
	suppressLid  bool
	lidError     string
	ownPath      string
	machineHasLid bool
	trayOn       bool
	enumCallback uintptr
	wndCallback  uintptr
	className    *uint16
)

func main() {
	if exe, err := os.Executable(); err == nil {
		ownPath, _ = filepath.Abs(exe)
	}
	machineHasLid = detectLid()
	loadConfig()
	className, _ = syscall.UTF16PtrFromString("NoSleepWindow")
	wndCallback = syscall.NewCallback(windowProc)
	enumCallback = syscall.NewCallback(enumWindow)
	instance, _, _ := pGetModule.Call(0)
	cursor, _, _ := pLoadCursor.Call(0, 32512)
	icon, _, _ := pLoadIcon.Call(0, 32512)
	class := wndClass{
		Size:       uint32(unsafe.Sizeof(wndClass{})),
		WndProc:    wndCallback,
		Instance:   instance,
		Icon:       icon,
		Cursor:     cursor,
		Background: colorWindow + 1,
		ClassName:  className,
		IconSm:     icon,
	}
	pRegisterClass.Call(uintptr(unsafe.Pointer(&class)))
	title, _ := syscall.UTF16PtrFromString("不许睡")
	hwnd, _, _ := pCreateWindow.Call(0, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(title)), wsOverlapped|wsVisible, 80, 80, 980, 680, 0, 0, instance, 0)
	mainWindow = hwnd
	pShowWindow.Call(hwnd, swShow)
	pUpdateWindow.Call(hwnd)
	var message msg
	for {
		ret, _, _ := pGetMessage.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		pTranslate.Call(uintptr(unsafe.Pointer(&message)))
		pDispatch.Call(uintptr(unsafe.Pointer(&message)))
	}
}

func windowProc(hwnd, message, wparam, lparam uintptr) uintptr {
	switch uint32(message) {
	case 0x0001: // WM_CREATE
		buildControls(hwnd)
		refreshCatalog()
		fillLists()
		applyPolicy()
		pSetTimer.Call(hwnd, 1, 3000, 0)
		addTray(hwnd)
		return 0
	case wmSize:
		layout(hwnd)
		return 0
	case wmTimer:
		refreshCatalog()
		fillLists()
		applyPolicy()
		return 0
	case wmCommand:
		onCommand(wparam)
		return 0
	case wmTray:
		onTray(hwnd, lparam)
		return 0
	case wmClose:
		if trayOn {
			pShowWindow.Call(hwnd, swHide)
			return 0
		}
		pDestroyWindow.Call(hwnd)
		return 0
	case wmDestroy:
		removeTray(hwnd)
		releaseSleep()
		restoreLid()
		pPostQuit.Call(0)
		return 0
	}
	ret, _, _ := pDefWindowProc.Call(hwnd, message, wparam, lparam)
	return ret
}

func buildControls(hwnd uintptr) {
	uiFont, _, _ = pCreateFont.Call(^uintptr(15), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 0, uintptr(unsafe.Pointer(mustUTF16("Microsoft YaHei UI"))))
	statusText = child(hwnd, "STATIC", "给我起床好好干活！", wsChild|wsVisible, idStatus)
	child(hwnd, "STATIC", "全部应用", wsChild|wsVisible, 201)
	leftList = child(hwnd, "LISTBOX", "", wsChild|wsVisible|wsBorder|wsVScroll|wsTabStop|lbsNotify|0x0100, idLeft)
	child(hwnd, "STATIC", "不许睡", wsChild|wsVisible, 202)
	rightList = child(hwnd, "LISTBOX", "", wsChild|wsVisible|wsBorder|wsVScroll|wsTabStop|lbsNotify|0x0100, idRight)
	child(hwnd, "STATIC", "电池电量下限", wsChild|wsVisible, 203)
	floorEdit = child(hwnd, "EDIT", strconv.Itoa(config.BatteryFloor), wsChild|wsVisible|wsBorder|wsTabStop|esCenter|esNumber, idFloor)
	child(hwnd, "STATIC", "%", wsChild|wsVisible, 204)
	lidCheck = child(hwnd, "BUTTON", "放心合盖，小心电量", wsChild|wsVisible|wsTabStop|bsAutoCheck, idLid)
	if config.LidEnabled && machineHasLid {
		pSendMessage.Call(lidCheck, bmSetCheck, bstChecked, 0)
	}
	note := "勾上后，合盖时整台电脑也不睡。点「保存」会要求管理员确认。左边列出当前打开的窗口。"
	if !machineHasLid {
		pShowWindow.Call(lidCheck, swHide)
		note = "左边列出当前打开的窗口。"
	}
	child(hwnd, "STATIC", note, wsChild|wsVisible, 205)
	resetButton = child(hwnd, "BUTTON", "恢复默认", wsChild|wsVisible|wsTabStop, idReset)
	saveButton = child(hwnd, "BUTTON", "保存", wsChild|wsVisible|wsTabStop, idSave)
	layout(hwnd)
}

func child(parent uintptr, className, title string, style uintptr, id int) uintptr {
	classPtr := mustUTF16(className)
	titlePtr := mustUTF16(title)
	hwnd, _, _ := pCreateWindow.Call(0, uintptr(unsafe.Pointer(classPtr)), uintptr(unsafe.Pointer(titlePtr)), style, 0, 0, 10, 10, parent, uintptr(id), 0, 0)
	runtime.KeepAlive(classPtr)
	runtime.KeepAlive(titlePtr)
	if uiFont != 0 {
		pSendMessage.Call(hwnd, wmSetFont, uiFont, 1)
	}
	return hwnd
}

func layout(hwnd uintptr) {
	var area rect
	pGetClientRect.Call(hwnd, uintptr(unsafe.Pointer(&area)))
	width := int(area.Right)
	height := int(area.Bottom)
	margin := 16
	move(statusText, margin, 12, width-margin*2, 36)
	listTop := 78
	listHeight := height - 250
	if listHeight < 180 {
		listHeight = 180
	}
	colGap := 16
	colWidth := (width - margin*2 - colGap) / 2
	move(findStatic(hwnd, 201), margin, 52, colWidth, 22)
	move(leftList, margin, listTop, colWidth, listHeight)
	rightX := margin + colWidth + colGap
	move(findStatic(hwnd, 202), rightX, 52, colWidth, 22)
	move(rightList, rightX, listTop, colWidth, listHeight)
	controls := listTop + listHeight + 14
	move(findStatic(hwnd, 203), rightX, controls, 110, 24)
	move(floorEdit, rightX+116, controls-2, 48, 24)
	move(findStatic(hwnd, 204), rightX+170, controls, 24, 24)
	move(lidCheck, rightX, controls+32, colWidth, 24)
	move(findStatic(hwnd, 205), rightX, controls+60, colWidth, 36)
	move(resetButton, width-margin-72-8-96, height-margin-34, 96, 32)
	move(saveButton, width-margin-72, height-margin-34, 72, 32)
}

func findStatic(hwnd uintptr, id int) uintptr {
	getDlgItem := user32.NewProc("GetDlgItem")
	handle, _, _ := getDlgItem.Call(hwnd, uintptr(id))
	return handle
}

func move(hwnd uintptr, x, y, w, h int) {
	if hwnd == 0 {
		return
	}
	pMoveWindow.Call(hwnd, uintptr(x), uintptr(y), uintptr(w), uintptr(h), 1)
}

func onCommand(wparam uintptr) {
	if filling {
		return
	}
	id := wparam & 0xFFFF
	note := (wparam >> 16) & 0xFFFF
	switch id {
	case idLeft:
		if note == 1 || note == 2 {
			moveToRight()
		}
	case idRight:
		if note == 1 || note == 2 {
			moveToLeft()
		}
	case idSave:
		start()
	case idReset:
		restoreDefaults()
	}
}

func moveToRight() {
	index := selectedIndex(leftList)
	items := leftItems()
	if index < 0 || index >= len(items) {
		return
	}
	chosen := items[index]
	if !contains(config.Apps, chosen.Path) {
		config.Apps = append(config.Apps, chosen)
		saveConfig()
	}
	fillLists()
}

func moveToLeft() {
	index := selectedIndex(rightList)
	if index < 0 || index >= len(config.Apps) {
		return
	}
	config.Apps = append(config.Apps[:index], config.Apps[index+1:]...)
	saveConfig()
	fillLists()
}

func start() {
	text := windowText(floorEdit)
	floor, err := strconv.Atoi(strings.TrimSpace(text))
	if err != nil || floor < 1 || floor > 90 {
		alert("电量下限请填 1 到 90 的整数")
		return
	}
	config.BatteryFloor = floor
	config.LidEnabled = machineHasLid && isChecked(lidCheck)
	config.Paused = false
	suppressLid = false
	lidError = ""
	saveConfig()
	applyPolicy()
	pShowWindow.Call(mainWindow, swMinimize)
}

func restoreDefaults() {
	releaseSleep()
	config.Apps = nil
	config.Manual = false
	config.Paused = false
	config.LidEnabled = false
	config.LidRestore = nil
	suppressLid = true
	lidError = ""
	pSendMessage.Call(lidCheck, bmSetCheck, 0, 0)
	saveConfig()
	fillLists()
	if !machineHasLid {
		applyPolicy()
		return
	}
	ac, dc, ok := readLid()
	if ok && (ac != 1 || dc != 1) {
		if err := writeLid(1, 1); err != nil {
			alert("名单已清空。合盖设置没能恢复：" + err.Error())
		}
	}
	applyPolicy()
}

func alert(text string) {
	body := mustUTF16(text)
	title := mustUTF16("不许睡")
	pMessageBox.Call(mainWindow, uintptr(unsafe.Pointer(body)), uintptr(unsafe.Pointer(title)), 0)
	runtime.KeepAlive(body)
	runtime.KeepAlive(title)
}

var filling bool

func fillLists() {
	filling = true
	defer func() { filling = false }()
	refill(leftList, leftItems())
	refill(rightList, config.Apps)
}

func leftItems() []appItem {
	chosen := map[string]bool{}
	for _, app := range config.Apps {
		chosen[strings.ToLower(app.Path)] = true
	}
	var items []appItem
	for _, app := range catalog {
		if !chosen[strings.ToLower(app.Path)] {
			items = append(items, app)
		}
	}
	return items
}

func refill(list uintptr, items []appItem) {
	pSendMessage.Call(list, lbReset, 0, 0)
	running := runningPaths()
	for _, item := range items {
		label := item.Name
		if running[strings.ToLower(item.Path)] {
			label += "    运行中"
		}
		ptr := mustUTF16(label)
		pSendMessage.Call(list, lbAddString, 0, uintptr(unsafe.Pointer(ptr)))
		runtime.KeepAlive(ptr)
	}
}

func selectedIndex(list uintptr) int {
	index, _, _ := pSendMessage.Call(list, lbGetCurSel, 0, 0)
	if int32(index) < 0 {
		return -1
	}
	return int(index)
}

func applyPolicy() {
	batteryOn, percent, known := battery()
	running := runningPaths()
	selectedRunning := false
	for _, app := range config.Apps {
		if running[strings.ToLower(app.Path)] {
			selectedRunning = true
			break
		}
	}
	hold := shouldHold(config.Paused, config.Manual, config.BatteryFloor, batteryOn, known, percent, selectedRunning)
	if hold {
		pSetExecState.Call(esContinuous | esSystem)
		holding = true
	} else if holding {
		releaseSleep()
	}
	syncLid(hold && config.LidEnabled)
	already := false
	if config.LidEnabled {
		ac, dc, ok := cachedLid()
		already = ok && ac == 0 && dc == 0
	}
	owned := config.LidRestore != nil && config.LidRestore.Active
	setStatus(describe(config.Paused, config.Manual, hold, selectedRunning, config.LidEnabled, owned, already, config.BatteryFloor, percent, batteryOn, known, lidError))
}

func releaseSleep() {
	pSetExecState.Call(esContinuous)
	holding = false
}

func syncLid(want bool) {
	if !machineHasLid {
		return
	}
	if want {
		if config.LidRestore != nil && config.LidRestore.Active {
			return
		}
		if suppressLid {
			return
		}
		ac, dc, ok := readLid()
		if !ok {
			return
		}
		if ac == 0 && dc == 0 {
			return
		}
		config.LidRestore = &lidRestore{AC: ac, DC: dc, Active: true}
		saveConfig()
		if err := writeLid(0, 0); err != nil {
			config.LidRestore = nil
			saveConfig()
			suppressLid = true
			lidError = "合盖没改成：" + err.Error()
		}
		return
	}
	restoreLid()
}

func restoreLid() {
	if config.LidRestore == nil || !config.LidRestore.Active {
		return
	}
	prev := *config.LidRestore
	if err := writeLid(prev.AC, prev.DC); err != nil {
		lidError = "没能恢复原来的合盖设置：" + err.Error()
		return
	}
	config.LidRestore = nil
	lidError = ""
	saveConfig()
}

var (
	lidCacheAC   int
	lidCacheDC   int
	lidCacheOK   bool
	lidCacheTick int
)

func cachedLid() (int, int, bool) {
	lidCacheTick++
	if !lidCacheOK || lidCacheTick%5 == 1 {
		ac, dc, ok := readLid()
		if ok {
			lidCacheAC, lidCacheDC, lidCacheOK = ac, dc, true
		}
	}
	return lidCacheAC, lidCacheDC, lidCacheOK
}

func readLid() (int, int, bool) {
	ac, err1 := powerIndex(false)
	dc, err2 := powerIndex(true)
	if err1 != nil || err2 != nil {
		return 0, 0, false
	}
	return ac, dc, true
}

var indexPattern = regexp.MustCompile(`0x[0-9a-fA-F]+|\b\d+\b`)

func powerIndex(dc bool) (int, error) {
	flag := "/GETACVALUEINDEX"
	if dc {
		flag = "/GETDCVALUEINDEX"
	}
	command := exec.Command("powercfg", flag, "SCHEME_CURRENT", "SUB_BUTTONS", "LIDACTION")
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, err := command.Output()
	if err != nil {
		return 0, err
	}
	matches := indexPattern.FindAllString(string(out), -1)
	if len(matches) == 0 {
		return 0, fmt.Errorf("读不到合盖设置")
	}
	raw := matches[len(matches)-1]
	var value int64
	var parseErr error
	if strings.HasPrefix(strings.ToLower(raw), "0x") {
		value, parseErr = strconv.ParseInt(raw[2:], 16, 32)
	} else {
		value, parseErr = strconv.ParseInt(raw, 10, 32)
	}
	if parseErr != nil {
		return 0, parseErr
	}
	return int(value), nil
}

func writeLid(ac, dc int) error {
	script := fmt.Sprintf("powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION %d & powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION %d & powercfg /SETACTIVE SCHEME_CURRENT", ac, dc)
	return runElevated("cmd.exe", "/c "+script)
}

func runElevated(file, params string) error {
	verb := mustUTF16("runas")
	filePtr := mustUTF16(file)
	paramPtr := mustUTF16(params)
	info := shellExecInfo{
		FMask:      seeNoClose,
		Verb:       verb,
		File:       filePtr,
		Parameters: paramPtr,
		Show:       0,
	}
	info.CbSize = uint32(unsafe.Sizeof(info))
	ret, _, _ := pShellExec.Call(uintptr(unsafe.Pointer(&info)))
	runtime.KeepAlive(verb)
	runtime.KeepAlive(filePtr)
	runtime.KeepAlive(paramPtr)
	if ret == 0 {
		return fmt.Errorf("没有获得管理员确认")
	}
	if info.Process != 0 {
		pWait.Call(info.Process, 0xFFFFFFFF)
		var code uint32
		pExitCode.Call(info.Process, uintptr(unsafe.Pointer(&code)))
		pCloseHandle.Call(info.Process)
		if code != 0 {
			return fmt.Errorf("powercfg 退出码 %d", code)
		}
	}
	return nil
}

func battery() (onBattery bool, percent int, known bool) {
	var status systemPower
	ret, _, _ := pPowerStatus.Call(uintptr(unsafe.Pointer(&status)))
	if ret == 0 {
		return false, 0, false
	}
	if status.BatteryLifePercent <= 100 {
		percent = int(status.BatteryLifePercent)
		known = true
	}
	return status.ACLineStatus == 0, percent, known
}

func refreshCatalog() {
	paths := windowProcessPaths()
	seen := map[string]bool{}
	for _, item := range catalog {
		seen[strings.ToLower(item.Path)] = true
	}
	for _, item := range config.Apps {
		seen[strings.ToLower(item.Path)] = true
	}
	for path := range paths {
		key := strings.ToLower(path)
		if seen[key] || strings.EqualFold(path, ownPath) {
			continue
		}
		seen[key] = true
		catalog = append(catalog, appItem{Name: displayName(path), Path: path})
	}
	sortApps(catalog)
}

func runningPaths() map[string]bool {
	return windowProcessPaths()
}

func windowProcessPaths() map[string]bool {
	visiblePIDs = nil
	pEnumWindows.Call(enumCallback, 0)
	found := map[string]bool{}
	for _, pid := range visiblePIDs {
		path := processPath(pid)
		if path != "" {
			found[path] = true
		}
	}
	return found
}

var visiblePIDs []uint32

func enumWindow(hwnd, lparam uintptr) uintptr {
	if visible, _, _ := pIsWindowVisible.Call(hwnd); visible == 0 {
		return 1
	}
	if length, _, _ := pGetWindowTextLn.Call(hwnd); length == 0 {
		return 1
	}
	var pid uint32
	pGetWindowPID.Call(hwnd, uintptr(unsafe.Pointer(&pid)))
	runtime.KeepAlive(&pid)
	if pid != 0 {
		current, _, _ := pCurrentPID.Call()
		if uint32(current) != pid {
			visiblePIDs = append(visiblePIDs, pid)
		}
	}
	return 1
}

func processPath(pid uint32) string {
	handle, _, _ := pOpenProcess.Call(0x1000, 0, uintptr(pid))
	if handle == 0 {
		return ""
	}
	defer pCloseHandle.Call(handle)
	buf := make([]uint16, 1024)
	size := uint32(len(buf))
	ret, _, _ := pQueryImage.Call(handle, 0, uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&size)))
	runtime.KeepAlive(buf)
	runtime.KeepAlive(&size)
	if ret == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf[:size])
}

func displayName(path string) string {
	base := filepath.Base(path)
	return strings.TrimSuffix(base, filepath.Ext(base))
}

func sortApps(items []appItem) {
	for i := 1; i < len(items); i++ {
		item := items[i]
		j := i
		for j > 0 && strings.ToLower(items[j-1].Name) > strings.ToLower(item.Name) {
			items[j] = items[j-1]
			j--
		}
		items[j] = item
	}
}

func contains(items []appItem, path string) bool {
	for _, item := range items {
		if strings.EqualFold(item.Path, path) {
			return true
		}
	}
	return false
}

func detectLid() bool {
	getCaps := powrprof.NewProc("GetPwrCapabilities")
	buf := make([]byte, 64)
	ret, _, _ := getCaps.Call(uintptr(unsafe.Pointer(&buf[0])))
	if ret != 0 {
		return buf[2] != 0
	}
	_, _, ok := readLid()
	return ok
}

func loadConfig() {
	config = appConfig{BatteryFloor: 20, LidEnabled: machineHasLid}
	data, err := os.ReadFile(configPath())
	if err != nil {
		return
	}
	_ = json.Unmarshal(data, &config)
	if config.BatteryFloor < 1 || config.BatteryFloor > 90 {
		config.BatteryFloor = 20
	}
	if !machineHasLid {
		config.LidEnabled = false
	}
}

func saveConfig() {
	dir := filepath.Dir(configPath())
	_ = os.MkdirAll(dir, 0o755)
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(configPath(), data, 0o644)
}

func configPath() string {
	base, err := os.UserConfigDir()
	if err != nil {
		base = os.TempDir()
	}
	return filepath.Join(base, "不许睡", "config.json")
}

func setStatus(text string) {
	_ = text
}

func windowText(hwnd uintptr) string {
	buf := make([]uint16, 64)
	pGetWindowText.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	runtime.KeepAlive(buf)
	return syscall.UTF16ToString(buf)
}

func isChecked(hwnd uintptr) bool {
	state, _, _ := pSendMessage.Call(hwnd, 0x00F0, 0, 0) // BM_GETCHECK
	return state == bstChecked
}

func mustUTF16(value string) *uint16 {
	ptr, err := syscall.UTF16PtrFromString(value)
	if err != nil {
		ptr, _ = syscall.UTF16PtrFromString("")
	}
	return ptr
}

func addTray(hwnd uintptr) {
	icon, _, _ := pLoadIcon.Call(0, 32512)
	data := notifyIcon{
		CbSize:   uint32(unsafe.Sizeof(notifyIcon{})),
		Hwnd:     hwnd,
		UID:      1,
		Flags:    nifMessage | nifIcon | nifTip,
		Callback: wmTray,
		Icon:     icon,
	}
	tip, _ := syscall.UTF16FromString("不许睡")
	copy(data.Tip[:], tip)
	ret, _, _ := pNotifyIcon.Call(nimAdd, uintptr(unsafe.Pointer(&data)))
	runtime.KeepAlive(tip)
	trayOn = ret != 0
}

func removeTray(hwnd uintptr) {
	if !trayOn {
		return
	}
	data := notifyIcon{CbSize: uint32(unsafe.Sizeof(notifyIcon{})), Hwnd: hwnd, UID: 1}
	pNotifyIcon.Call(nimDelete, uintptr(unsafe.Pointer(&data)))
	trayOn = false
}

func onTray(hwnd, lparam uintptr) {
	if lparam == wmLButtonUp {
		pShowWindow.Call(hwnd, swShow)
		pSetForeground.Call(hwnd)
		return
	}
	if lparam != wmRButtonUp {
		return
	}
	menu, _, _ := pCreatePopup.Call()
	appendItem(menu, 10, "打开窗口")
	if config.Paused {
		appendItem(menu, 11, "继续不许睡")
	} else {
		appendItem(menu, 11, "先允许睡")
	}
	if config.Manual {
		appendItem(menu, 12, "可以睡了")
	} else {
		appendItem(menu, 12, "现在不许睡")
	}
	appendItem(menu, 13, "退出")
	var cursor point
	pGetCursorPos.Call(uintptr(unsafe.Pointer(&cursor)))
	pSetForeground.Call(hwnd)
	cmd, _, _ := pTrackPopup.Call(menu, tpmReturn, uintptr(cursor.X), uintptr(cursor.Y), 0, hwnd, 0)
	pDestroyMenu.Call(menu)
	switch cmd {
	case 10:
		pShowWindow.Call(hwnd, swShow)
		pSetForeground.Call(hwnd)
	case 11:
		config.Paused = !config.Paused
		saveConfig()
		applyPolicy()
	case 12:
		config.Manual = !config.Manual
		if config.Manual {
			config.Paused = false
		}
		saveConfig()
		applyPolicy()
	case 13:
		pDestroyWindow.Call(hwnd)
	}
}

func appendItem(menu uintptr, id uintptr, title string) {
	ptr := mustUTF16(title)
	pAppendMenu.Call(menu, mfString, id, uintptr(unsafe.Pointer(ptr)))
	runtime.KeepAlive(ptr)
}
