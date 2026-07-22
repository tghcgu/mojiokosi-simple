param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) "transcripts"),
    [int]$PollMilliseconds = 200
)

$ErrorActionPreference = "Stop"

$createdNewInstance = $false
$instanceMutex = New-Object System.Threading.Mutex($true, "Local\MojiokosiSimple", [ref]$createdNewInstance)
if (-not $createdNewInstance) {
    $instanceMutex.Dispose()
    exit
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$transcriptPath = Join-Path $OutputDirectory "caption-$timestamp.txt"
New-Item -ItemType File -Path $transcriptPath -Force | Out-Null

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class NativeWindowTools
{
    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int index);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int index, int newStyle);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out NativeRect rect);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", EntryPoint = "SendMessage")]
    private static extern IntPtr SendMessagePoint(IntPtr hWnd, uint message, IntPtr wParam, ref NativePoint lParam);

    public static int GetRichEditScrollY(IntPtr hWnd)
    {
        NativePoint point = new NativePoint();
        SendMessagePoint(hWnd, EM_GETSCROLLPOS, IntPtr.Zero, ref point);
        return point.Y;
    }

    public static void SetRichEditScrollY(IntPtr hWnd, int y)
    {
        NativePoint point = new NativePoint();
        point.Y = Math.Max(0, y);
        SendMessagePoint(hWnd, EM_SETSCROLLPOS, IntPtr.Zero, ref point);
    }

    public const byte VK_LWIN = 0x5B;
    public const byte VK_CONTROL = 0x11;
    public const byte VK_L = 0x4C;
    public const int VK_LBUTTON = 0x01;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_FRAMECHANGED = 0x0020;
    public const uint WM_CLOSE = 0x0010;
    public const uint WM_NCLBUTTONDOWN = 0x00A1;
    public const int HTCAPTION = 0x0002;
    public const int HTLEFT = 0x000A;
    public const int HTRIGHT = 0x000B;
    public const int HTTOP = 0x000C;
    public const int HTTOPLEFT = 0x000D;
    public const int HTTOPRIGHT = 0x000E;
    public const int HTBOTTOM = 0x000F;
    public const int HTBOTTOMLEFT = 0x0010;
    public const int HTBOTTOMRIGHT = 0x0011;
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_APPWINDOW = 0x00040000;
    private const uint EM_GETSCROLLPOS = 0x04DD;
    private const uint EM_SETSCROLLPOS = 0x04DE;
}

public static class ForegroundWinArrowMonitor
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const uint WM_QUIT = 0x0012;
    private const int VK_SHIFT = 0x10;
    private const int VK_CONTROL = 0x11;
    private const int VK_MENU = 0x12;
    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;
    private const int VK_LSHIFT = 0xA0;
    private const int VK_RSHIFT = 0xA1;
    private const int VK_LCONTROL = 0xA2;
    private const int VK_RCONTROL = 0xA3;
    private const int VK_LMENU = 0xA4;
    private const int VK_RMENU = 0xA5;
    public const int VK_LEFT = 0x25;
    public const int VK_UP = 0x26;
    public const int VK_RIGHT = 0x27;
    public const int VK_DOWN = 0x28;

    public sealed class WinArrowCommand
    {
        public int VirtualKey { get; private set; }
        public bool ShiftPressed { get; private set; }
        public int WindowLeft { get; private set; }
        public int WindowTop { get; private set; }
        public int WindowRight { get; private set; }
        public int WindowBottom { get; private set; }
        public long EnqueuedTimestamp { get; private set; }

        public WinArrowCommand(int virtualKey, bool shiftPressed, NativeWindowTools.NativeRect bounds)
        {
            VirtualKey = virtualKey;
            ShiftPressed = shiftPressed;
            WindowLeft = bounds.Left;
            WindowTop = bounds.Top;
            WindowRight = bounds.Right;
            WindowBottom = bounds.Bottom;
            EnqueuedTimestamp = Stopwatch.GetTimestamp();
        }
    }

    private delegate IntPtr LowLevelKeyboardProc(int code, IntPtr message, IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardHookData
    {
        public uint VirtualKey;
        public uint ScanCode;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HookPoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeMessage
    {
        public IntPtr Window;
        public uint Message;
        public UIntPtr WParam;
        public IntPtr LParam;
        public uint Time;
        public HookPoint Point;
        public uint Private;
    }

    private static readonly object SyncRoot = new object();
    private static readonly Queue<WinArrowCommand> PendingKeys = new Queue<WinArrowCommand>();
    private static readonly LowLevelKeyboardProc HookProcedure = HandleKeyboardMessage;
    private static readonly ManualResetEvent HookReady = new ManualResetEvent(false);
    private static IntPtr hookHandle = IntPtr.Zero;
    private static IntPtr targetWindow = IntPtr.Zero;
    private static Thread hookThread;
    private static uint hookThreadId;
    private static bool stopRequested;
    private static int heldArrowMask;
    private static int capturedArrowMask;
    private static int heldModifierMask;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int hookType, LowLevelKeyboardProc callback, IntPtr module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetMessage(out NativeMessage message, IntPtr window, uint minimum, uint maximum);

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(out NativeMessage message, IntPtr window, uint minimum, uint maximum, uint remove);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref NativeMessage message);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref NativeMessage message);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostThreadMessage(uint threadId, uint message, UIntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string moduleName);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    public static bool Install(IntPtr window)
    {
        Uninstall();

        Thread newThread;
        lock (SyncRoot)
        {
            targetWindow = window;
            PendingKeys.Clear();
            heldArrowMask = 0;
            capturedArrowMask = 0;
            heldModifierMask = 0;
            stopRequested = false;
            HookReady.Reset();
            newThread = new Thread(RunHookThread);
            newThread.IsBackground = true;
            newThread.Name = "MojiokosiWinArrowMonitor";
            hookThread = newThread;
        }

        newThread.Start();
        if (!HookReady.WaitOne(3000))
        {
            Uninstall();
            return false;
        }

        lock (SyncRoot)
        {
            return hookHandle != IntPtr.Zero;
        }
    }

    public static void Uninstall()
    {
        IntPtr handleToRemove;
        Thread threadToStop;
        uint threadIdToStop;
        lock (SyncRoot)
        {
            stopRequested = true;
            handleToRemove = hookHandle;
            threadToStop = hookThread;
            threadIdToStop = hookThreadId;
            hookHandle = IntPtr.Zero;
            hookThread = null;
            hookThreadId = 0;
            targetWindow = IntPtr.Zero;
            PendingKeys.Clear();
            heldArrowMask = 0;
            capturedArrowMask = 0;
            heldModifierMask = 0;
        }

        if (handleToRemove != IntPtr.Zero)
        {
            UnhookWindowsHookEx(handleToRemove);
        }
        if (threadIdToStop != 0)
        {
            PostThreadMessage(threadIdToStop, WM_QUIT, UIntPtr.Zero, IntPtr.Zero);
        }
        if (threadToStop != null && threadToStop != Thread.CurrentThread && threadToStop.IsAlive)
        {
            threadToStop.Join(3000);
        }
    }

    public static WinArrowCommand TakePendingKey()
    {
        lock (SyncRoot)
        {
            if (PendingKeys.Count == 0)
            {
                return null;
            }

            WinArrowCommand command = PendingKeys.Peek();
            long minimumSettleTicks = Math.Max(1L, Stopwatch.Frequency / 20L);
            if (Stopwatch.GetTimestamp() - command.EnqueuedTimestamp < minimumSettleTicks)
            {
                return null;
            }
            return PendingKeys.Dequeue();
        }
    }

    private static IntPtr HandleKeyboardMessage(int code, IntPtr message, IntPtr data)
    {
        bool suppressRepeatedArrow = false;
        if (code >= 0)
        {
            int messageCode = unchecked((int)message.ToInt64());
            KeyboardHookData key = (KeyboardHookData)Marshal.PtrToStructure(data, typeof(KeyboardHookData));
            bool isKeyDown = messageCode == WM_KEYDOWN || messageCode == WM_SYSKEYDOWN;
            bool isKeyUp = messageCode == WM_KEYUP || messageCode == WM_SYSKEYUP;
            int modifierMask = GetModifierMask(key.VirtualKey);
            if (modifierMask != 0)
            {
                lock (SyncRoot)
                {
                    if (isKeyDown)
                    {
                        heldModifierMask |= modifierMask;
                    }
                    else if (isKeyUp)
                    {
                        heldModifierMask &= ~modifierMask;
                    }
                }
            }
            else
            {
                int arrowMask = GetArrowMask(key.VirtualKey);
                if (arrowMask != 0)
                {
                    if (isKeyUp)
                    {
                        lock (SyncRoot)
                        {
                            heldArrowMask &= ~arrowMask;
                            capturedArrowMask &= ~arrowMask;
                        }
                    }
                    else if (isKeyDown)
                    {
                        bool firstPress;
                        bool wasCaptured;
                        lock (SyncRoot)
                        {
                            firstPress = (heldArrowMask & arrowMask) == 0;
                            wasCaptured = (capturedArrowMask & arrowMask) != 0;
                            heldArrowMask |= arrowMask;
                        }

                        if (!firstPress && wasCaptured)
                        {
                            suppressRepeatedArrow = true;
                            return new IntPtr(1);
                        }

                        int shortcutKind = GetWinShortcutKind();
                        bool supportedShortcut = shortcutKind == 1 ||
                            (shortcutKind == 2 &&
                                (key.VirtualKey == VK_LEFT || key.VirtualKey == VK_RIGHT));
                        if (supportedShortcut && GetForegroundWindow() == targetWindow)
                        {
                            if (!firstPress)
                            {
                                suppressRepeatedArrow = true;
                            }
                            else
                            {
                                NativeWindowTools.NativeRect windowBounds = new NativeWindowTools.NativeRect();
                                if (NativeWindowTools.GetWindowRect(targetWindow, out windowBounds))
                                {
                                    lock (SyncRoot)
                                    {
                                        if (PendingKeys.Count < 8)
                                        {
                                            capturedArrowMask |= arrowMask;
                                            PendingKeys.Enqueue(new WinArrowCommand(
                                                unchecked((int)key.VirtualKey),
                                                shortcutKind == 2,
                                                windowBounds
                                            ));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if (suppressRepeatedArrow)
        {
            return new IntPtr(1);
        }
        return CallNextHookEx(IntPtr.Zero, code, message, data);
    }

    private static void RunHookThread()
    {
        IntPtr installedHook = IntPtr.Zero;
        try
        {
            uint currentThreadId = GetCurrentThreadId();
            NativeMessage firstMessage;
            PeekMessage(out firstMessage, IntPtr.Zero, 0, 0, 0);
            lock (SyncRoot)
            {
                hookThreadId = currentThreadId;
                if (stopRequested)
                {
                    HookReady.Set();
                    return;
                }
            }

            using (Process process = Process.GetCurrentProcess())
            using (ProcessModule module = process.MainModule)
            {
                installedHook = SetWindowsHookEx(
                    WH_KEYBOARD_LL,
                    HookProcedure,
                    GetModuleHandle(module.ModuleName),
                    0
                );
            }

            lock (SyncRoot)
            {
                if (stopRequested)
                {
                    HookReady.Set();
                    return;
                }
                hookHandle = installedHook;
            }
            HookReady.Set();

            if (installedHook == IntPtr.Zero)
            {
                return;
            }

            NativeMessage message;
            while (GetMessage(out message, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
        }
        finally
        {
            lock (SyncRoot)
            {
                if (hookHandle == installedHook)
                {
                    hookHandle = IntPtr.Zero;
                }
                if (hookThread == Thread.CurrentThread)
                {
                    hookThread = null;
                    hookThreadId = 0;
                }
            }
            if (installedHook != IntPtr.Zero)
            {
                UnhookWindowsHookEx(installedHook);
            }
            HookReady.Set();
        }
    }

    private static int GetWinShortcutKind()
    {
        lock (SyncRoot)
        {
            const int winMask = 0x0003;
            const int shiftMask = 0x001C;
            const int unsupportedModifierMask = 0x1FE0;
            if ((heldModifierMask & winMask) == 0 ||
                (heldModifierMask & unsupportedModifierMask) != 0)
            {
                return 0;
            }
            return (heldModifierMask & shiftMask) != 0 ? 2 : 1;
        }
    }

    private static int GetArrowMask(uint virtualKey)
    {
        if (virtualKey == VK_LEFT) return 1;
        if (virtualKey == VK_UP) return 2;
        if (virtualKey == VK_RIGHT) return 4;
        if (virtualKey == VK_DOWN) return 8;
        return 0;
    }

    private static int GetModifierMask(uint virtualKey)
    {
        if (virtualKey == VK_LWIN) return 0x0001;
        if (virtualKey == VK_RWIN) return 0x0002;
        if (virtualKey == VK_SHIFT) return 0x0004;
        if (virtualKey == VK_LSHIFT) return 0x0008;
        if (virtualKey == VK_RSHIFT) return 0x0010;
        if (virtualKey == VK_CONTROL) return 0x0020;
        if (virtualKey == VK_LCONTROL) return 0x0040;
        if (virtualKey == VK_RCONTROL) return 0x0080;
        if (virtualKey == VK_MENU) return 0x0100;
        if (virtualKey == VK_LMENU) return 0x0200;
        if (virtualKey == VK_RMENU) return 0x0400;
        return 0;
    }
}
"@

function Test-LeftMousePressedSinceLastCheck {
    return ((([int][NativeWindowTools]::GetAsyncKeyState([NativeWindowTools]::VK_LBUTTON)) -band 0x0001) -ne 0)
}

function Send-LiveCaptionsShortcut {
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_LWIN, 0, 0, [UIntPtr]::Zero)
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_CONTROL, 0, 0, [UIntPtr]::Zero)
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_L, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_L, 0, [NativeWindowTools]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_CONTROL, 0, [NativeWindowTools]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_LWIN, 0, [NativeWindowTools]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
}

function Get-NotepadWindow {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$FilePath
    )

    $fileName = ""
    if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
        $fileName = [System.IO.Path]::GetFileName($FilePath)
    }

    try {
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero -and [NativeWindowTools]::IsWindow($Process.MainWindowHandle)) {
            return [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
        }
    } catch {
    }

    try {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($window in $windows) {
            try {
                $name = $window.Current.Name
                $className = $window.Current.ClassName
                $nativeWindowHandle = $window.Current.NativeWindowHandle
                $processName = ""

                try {
                    $processName = (Get-Process -Id $window.Current.ProcessId -ErrorAction Stop).ProcessName
                } catch {
                }

                $isSameProcess = ($null -ne $Process -and $window.Current.ProcessId -eq $Process.Id)
                $looksLikeNotepad = (
                    $processName -match "(?i)^notepad$" -or
                    $className -match "(?i)notepad|applicationframewindow" -or
                    $name -match "(?i)notepad" -or
                    $name -match "\u30e1\u30e2\u5e33"
                )
                $looksLikeTargetFile = (
                    -not [string]::IsNullOrWhiteSpace($fileName) -and
                    $name.IndexOf($fileName, [StringComparison]::OrdinalIgnoreCase) -ge 0
                )

                if ($nativeWindowHandle -ne 0 -and ($isSameProcess -or $looksLikeTargetFile -or ($looksLikeNotepad -and $looksLikeTargetFile))) {
                    return $window
                }
            } catch {
            }
        }
    } catch {
    }

    return $null
}

function Get-NotepadWindowHandle {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$FilePath
    )

    $window = Get-NotepadWindow -Process $Process -FilePath $FilePath
    if ($null -eq $window) {
        return [IntPtr]::Zero
    }

    try {
        if ($window.Current.NativeWindowHandle -ne 0) {
            return [IntPtr]$window.Current.NativeWindowHandle
        }
    } catch {
    }

    return [IntPtr]::Zero
}

function Get-ForegroundProcessId {
    $foregroundWindow = [NativeWindowTools]::GetForegroundWindow()
    if ($foregroundWindow -eq [IntPtr]::Zero) {
        return $null
    }

    [uint32]$processId = 0
    [NativeWindowTools]::GetWindowThreadProcessId($foregroundWindow, [ref]$processId) | Out-Null

    if ($processId -eq 0) {
        return $null
    }

    return [int]$processId
}

function Test-NotepadIsForeground {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$FilePath
    )

    if ($null -eq $Process) {
        return $false
    }

    $foregroundWindow = [NativeWindowTools]::GetForegroundWindow()
    $targetWindow = Get-NotepadWindowHandle -Process $Process -FilePath $FilePath
    if ($foregroundWindow -ne [IntPtr]::Zero -and $targetWindow -ne [IntPtr]::Zero -and $foregroundWindow -eq $targetWindow) {
        return $true
    }

    $foregroundProcessId = Get-ForegroundProcessId
    if ($null -eq $foregroundProcessId) {
        return $false
    }

    try {
        $Process.Refresh()
        return $foregroundProcessId -eq $Process.Id
    } catch {
    }

    return $false
}

function Invoke-AppActivate {
    param([object]$Target)

    try {
        $shell = New-Object -ComObject WScript.Shell
        return [bool]$shell.AppActivate($Target)
    } catch {
    }

    return $false
}

function Activate-NotepadForPaste {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$FilePath,
        [System.Windows.Automation.AutomationElement]$Window
    )

    $activated = $false

    if ($null -ne $Window) {
        try {
            if ($Window.Current.NativeWindowHandle -ne 0) {
                [NativeWindowTools]::SetForegroundWindow([IntPtr]$Window.Current.NativeWindowHandle) | Out-Null
                $activated = $true
            }
        } catch {
        }

        Start-Sleep -Milliseconds 80
        if (Focus-NotepadEditor -Window $Window) {
            $activated = $true
        }
    }

    if (-not $activated -and -not [string]::IsNullOrWhiteSpace($FilePath)) {
        $fileName = [System.IO.Path]::GetFileName($FilePath)
        $fileStem = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $activated = (Invoke-AppActivate -Target $fileName) -or (Invoke-AppActivate -Target $fileStem)
    }

    if (-not $activated -and $null -ne $Process) {
        try {
            $activated = Invoke-AppActivate -Target $Process.Id
        } catch {
        }
    }

    if (-not $activated) {
        $localizedNotepad = -join ([char]0x30e1, [char]0x30e2, [char]0x5e33)
        $activated = (Invoke-AppActivate -Target "Notepad") -or (Invoke-AppActivate -Target $localizedNotepad)
    }

    if ($activated) {
        Start-Sleep -Milliseconds 120
    }

    return $activated
}

function Focus-NotepadEditor {
    param([System.Windows.Automation.AutomationElement]$Window)

    if ($null -eq $Window) {
        return $false
    }

    $controlTypes = @(
        [System.Windows.Automation.ControlType]::Document,
        [System.Windows.Automation.ControlType]::Edit
    )

    foreach ($controlType in $controlTypes) {
        try {
            $condition = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                $controlType
            )
            $editor = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
            if ($null -ne $editor) {
                $editor.SetFocus()
                return $true
            }
        } catch {
        }
    }

    try {
        $Window.SetFocus()
        return $true
    } catch {
    }

    return $false
}

function Test-UiNoise {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $true
    }

    $clean = ($Text -replace "\s+", " ").Trim()
    $noisePatterns = @(
        "^(Live captions|Live Captions|\u30e9\u30a4\u30d6\s*\u30ad\u30e3\u30d7\u30b7\u30e7\u30f3)$",
        "^(Settings|Caption settings|Close|Minimize|Maximize|Restore|More options)$",
        "^(\u8a2d\u5b9a|\u9589\u3058\u308b|\u6700\u5c0f\u5316|\u6700\u5927\u5316|\u5143\u306b\u623b\u3059|\u305d\u306e\u4ed6\u306e\u30aa\u30d7\u30b7\u30e7\u30f3)$",
        "^(Ready to caption|No audio detected|Listening|Microphone)$",
        "^(\u30ad\u30e3\u30d7\u30b7\u30e7\u30f3\u306e\u6e96\u5099\u304c\u3067\u304d\u307e\u3057\u305f|\u97f3\u58f0\u304c\u691c\u51fa\u3055\u308c\u307e\u305b\u3093|\u805e\u304d\u53d6\u308a\u4e2d|\u30de\u30a4\u30af)$",
        "^\S+\s*\([^)]+\)\s*\u306e\s*\u30e9\u30a4\u30d6\s*\u30ad\u30e3\u30d7\u30b7\u30e7\u30f3\u3092\u8868\u793a\u3059\u308b\u6e96\u5099\u304c\u3067\u304d\u307e\u3057\u305f$"
    )

    foreach ($pattern in $noisePatterns) {
        if ($clean -match $pattern) {
            return $true
        }
    }

    $notepadUiPatterns = @(
        "\.txt\b",
        "Windows\s*\(CRLF\)",
        "\bUTF-8\b",
        "^\s*(Text|\u30c6\u30ad\u30b9\u30c8|Zoom|\u30ba\u30fc\u30e0)\s*$",
        "^(\u884c|Line)\s*\d+",
        "^(\u5217|Column)\s*\d+",
        "^(\u30bf\u30d6\u3092\u9589\u3058\u308b|Close tab)"
    )

    foreach ($pattern in $notepadUiPatterns) {
        if ($clean -match $pattern) {
            return $true
        }
    }

    return $false
}

function Normalize-CaptionText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -replace "`r`n|`r|`n", "`n").Split("`n")) {
        $trimmed = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            $lines.Add($trimmed)
        }
    }

    return ($lines -join "`r`n")
}

function Split-CaptionLines {
    param([string]$Text)

    $lines = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $lines
    }

    foreach ($line in ($Text -replace "`r`n|`r|`n", "`n").Split("`n")) {
        $trimmed = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not (Test-UiNoise $trimmed)) {
            $lines.Add($trimmed)
        }
    }

    return $lines
}

function Get-ElementTextItems {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [System.Windows.Automation.ControlType]$ControlType
    )

    $items = New-Object System.Collections.Generic.List[string]
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        $ControlType
    )

    try {
        $elements = $Element.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
        foreach ($child in $elements) {
            try {
                $text = Normalize-CaptionText $child.Current.Name
                if (-not (Test-UiNoise $text)) {
                    if ($items.Count -eq 0 -or $items[$items.Count - 1] -ne $text) {
                        $items.Add($text)
                    }
                }
            } catch {
            }
        }
    } catch {
    }

    return $items
}

function Test-PrefixRevision {
    param(
        [string]$Shorter,
        [string]$Longer
    )

    if ([string]::IsNullOrWhiteSpace($Shorter) -or [string]::IsNullOrWhiteSpace($Longer)) {
        return $false
    }

    $shortComparison = Get-ComparisonText $Shorter
    $longComparison = Get-ComparisonText $Longer

    if ($shortComparison.Length -eq 0 -or $longComparison.Length -eq 0) {
        return $false
    }

    if ($shortComparison.Length -ge $longComparison.Length) {
        return $false
    }

    if ($longComparison.StartsWith($shortComparison)) {
        return $true
    }

    if ($shortComparison.Length -lt 8) {
        return $false
    }

    $prefixLength = [Math]::Min($shortComparison.Length, $longComparison.Length)
    $longPrefix = $longComparison.Substring(0, $prefixLength)
    return (Test-SimilarText -Left $shortComparison -Right $longPrefix -MaxDistanceRatio 0.18)
}

function Compress-CaptionItems {
    param([System.Collections.Generic.List[string]]$Items)

    $compressed = New-Object System.Collections.Generic.List[string]

    foreach ($item in $Items) {
        $text = Normalize-CaptionText $item
        if (Test-UiNoise $text) {
            continue
        }

        $lines = @()
        foreach ($line in ($text -replace "`r`n|`r|`n", "`n").Split("`n")) {
            $trimmed = $line.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not (Test-UiNoise $trimmed)) {
                $lines += $trimmed
            }
        }

        foreach ($line in $lines) {
            $skipLine = $false

            for ($i = $compressed.Count - 1; $i -ge 0; $i--) {
                $existing = $compressed[$i]

                if ($existing -eq $line) {
                    $skipLine = $true
                    break
                }

                if (Test-PrefixRevision -Shorter $existing -Longer $line) {
                    $compressed.RemoveAt($i)
                    continue
                }

                if (Test-PrefixRevision -Shorter $line -Longer $existing) {
                    $skipLine = $true
                    break
                }
            }

            if (-not $skipLine) {
                $compressed.Add($line)
            }
        }
    }

    return $compressed
}

function Get-LiveCaptionsWindow {
    try {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($window in $windows) {
            try {
                $name = $window.Current.Name
                $className = $window.Current.ClassName
                $processName = ""

                try {
                    $processName = (Get-Process -Id $window.Current.ProcessId -ErrorAction Stop).ProcessName
                } catch {
                }

                $blockedProcess = $processName -match "(?i)^(notepad|cmd|powershell|pwsh|windowsterminal|openconsole)$"
                if ($blockedProcess) {
                    continue
                }

                $looksLikeOutputFile = $name -match "(?i)(livecaptions|caption)-\d{8}-\d{6}\.txt"
                if ($looksLikeOutputFile) {
                    continue
                }

                $processIsLiveCaptions = $processName -match "(?i)^livecaptions$"
                $titleIsLiveCaptions = (
                    $name -match "^(?i:live\s*captions)$" -or
                    $name -match "^\s*\u30e9\u30a4\u30d6\s*\u30ad\u30e3\u30d7\u30b7\u30e7\u30f3\s*$"
                )
                $classLooksUseful = $className -match "(?i)(livecaptions|xaml|corewindow|applicationframewindow)"

                if ($processIsLiveCaptions -or ($titleIsLiveCaptions -and $classLooksUseful)) {
                    return $window
                }
            } catch {
            }
        }
    } catch {
    }

    return $null
}

function Test-LiveCaptionsReadyForBackground {
    param([System.Windows.Automation.AutomationElement]$Window)

    if ($null -eq $Window) {
        return $false
    }

    foreach ($automationId in @("CaptionsTextBlock", "ReadyToCaptionTextBlock", "CaptionsScrollViewer")) {
        try {
            $condition = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
                $automationId
            )
            if ($null -ne $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)) {
                return $true
            }
        } catch {
        }
    }

    return $false
}

function Move-LiveCaptionsOffScreen {
    param([System.Windows.Automation.AutomationElement]$Window)

    if ($null -eq $Window) {
        return
    }

    try {
        $handle = [IntPtr]$Window.Current.NativeWindowHandle
        if ($handle -eq [IntPtr]::Zero) {
            return
        }

        $extendedStyle = [NativeWindowTools]::GetWindowLong($handle, [NativeWindowTools]::GWL_EXSTYLE)
        $toolWindowStyle = ($extendedStyle -band (-bnot [NativeWindowTools]::WS_EX_APPWINDOW)) -bor
            [NativeWindowTools]::WS_EX_TOOLWINDOW
        if ($toolWindowStyle -ne $extendedStyle) {
            [NativeWindowTools]::SetWindowLong(
                $handle,
                [NativeWindowTools]::GWL_EXSTYLE,
                $toolWindowStyle
            ) | Out-Null
        }

        $flags = [NativeWindowTools]::SWP_NOSIZE -bor
            [NativeWindowTools]::SWP_NOZORDER -bor
            [NativeWindowTools]::SWP_NOACTIVATE -bor
            [NativeWindowTools]::SWP_FRAMECHANGED
        [NativeWindowTools]::SetWindowPos($handle, [IntPtr]::Zero, -32000, -32000, 0, 0, $flags) | Out-Null
    } catch {
    }
}

function Close-LiveCaptions {
    param([int]$ProcessId = 0)

    $window = Get-LiveCaptionsWindow
    if ($null -ne $window -and $ProcessId -gt 0) {
        try {
            if ($window.Current.ProcessId -ne $ProcessId) {
                $window = $null
            }
        } catch {
            $window = $null
        }
    }

    if ($null -ne $window) {
        try {
            $handle = [IntPtr]$window.Current.NativeWindowHandle
            if ($handle -ne [IntPtr]::Zero) {
                [NativeWindowTools]::PostMessage(
                    $handle,
                    [NativeWindowTools]::WM_CLOSE,
                    [IntPtr]::Zero,
                    [IntPtr]::Zero
                ) | Out-Null
            }
        } catch {
        }
    }

    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $targetProcess = if ($ProcessId -gt 0) {
            Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        } else {
            Get-Process -Name "LiveCaptions" -ErrorAction SilentlyContinue
        }
        if ($null -eq $targetProcess) {
            return
        }
        Start-Sleep -Milliseconds 100
    }

    if ($ProcessId -gt 0) {
        Get-Process -Id $ProcessId -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    } else {
        Get-Process -Name "LiveCaptions" -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Get-LiveCaptionSnapshot {
    param([System.Windows.Automation.AutomationElement]$Window)

    $textItems = Get-ElementTextItems -Element $Window -ControlType ([System.Windows.Automation.ControlType]::Text)

    if ($textItems.Count -eq 0) {
        $textItems = Get-ElementTextItems -Element $Window -ControlType ([System.Windows.Automation.ControlType]::Document)
    }

    if ($textItems.Count -eq 0) {
        return ""
    }

    $captionItems = Compress-CaptionItems -Items $textItems

    if ($captionItems.Count -eq 0) {
        return ""
    }

    return ($captionItems -join "`r`n")
}

function Get-AddedText {
    param(
        [string]$Previous,
        [string]$Current
    )

    if ([string]::IsNullOrEmpty($Current)) {
        return ""
    }

    if ([string]::IsNullOrEmpty($Previous)) {
        return $Current
    }

    if ($Current -eq $Previous) {
        return ""
    }

    if ($Current.StartsWith($Previous)) {
        return $Current.Substring($Previous.Length)
    }

    if ($Previous.Contains($Current)) {
        return ""
    }

    $max = [Math]::Min($Previous.Length, $Current.Length)
    for ($length = $max; $length -gt 0; $length--) {
        if ($Previous.Substring($Previous.Length - $length) -eq $Current.Substring(0, $length)) {
            return $Current.Substring($length)
        }
    }

    return "`r`n$Current"
}

function Get-LevenshteinDistance {
    param(
        [string]$Left,
        [string]$Right
    )

    if ($null -eq $Left) {
        $Left = ""
    }
    if ($null -eq $Right) {
        $Right = ""
    }

    $leftLength = $Left.Length
    $rightLength = $Right.Length

    if ($leftLength -eq 0) {
        return $rightLength
    }
    if ($rightLength -eq 0) {
        return $leftLength
    }

    $previous = New-Object int[] ($rightLength + 1)
    $current = New-Object int[] ($rightLength + 1)

    for ($j = 0; $j -le $rightLength; $j++) {
        $previous[$j] = $j
    }

    for ($i = 1; $i -le $leftLength; $i++) {
        $current[0] = $i

        for ($j = 1; $j -le $rightLength; $j++) {
            $cost = 1
            if ($Left[$i - 1] -eq $Right[$j - 1]) {
                $cost = 0
            }

            $deleteCost = $previous[$j] + 1
            $insertCost = $current[$j - 1] + 1
            $replaceCost = $previous[$j - 1] + $cost
            $current[$j] = [Math]::Min([Math]::Min($deleteCost, $insertCost), $replaceCost)
        }

        $swap = $previous
        $previous = $current
        $current = $swap
    }

    return $previous[$rightLength]
}

function Get-ComparisonText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    return (($Text -replace "\s+", "") -replace "[\u3001\u3002\uff0c\uff0e,\.]", "")
}

function Test-StableCaptionLine {
    param([string]$Text)

    $comparison = Get-ComparisonText $Text
    if ($comparison.Length -ge 12) {
        return $true
    }

    return ($Text.Trim() -match "[\u3002\uff0e\.\!\?\uff01\uff1f]$")
}

function Test-CompleteCaptionLine {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return ($Text.Trim() -match "[\u3002\uff0e\.\!\?\uff01\uff1f]$")
}

function Test-RescuableCaptionLine {
    param([string]$Text)

    $comparison = Get-ComparisonText $Text
    if ($comparison.Length -ge 8) {
        return $true
    }

    return (Test-CompleteCaptionLine $Text)
}

function Get-TranscriptText {
    param(
        [string]$Captured,
        [string]$Pending,
        [switch]$IncludePending
    )

    $text = ""
    if ($null -ne $Captured) {
        $text = $Captured
    }

    if ($IncludePending -and -not [string]::IsNullOrWhiteSpace($Pending)) {
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $Pending
        }

        $capturedLines = @(
            ($text -replace "`r`n|`r|`n", "`n").Split("`n") |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        if ($capturedLines.Count -gt 0) {
            $lastCapturedLine = $capturedLines[$capturedLines.Count - 1]
            if ($lastCapturedLine -eq $Pending -or
                (Test-PrefixRevision -Shorter $Pending -Longer $lastCapturedLine)) {
                return $text
            }

            if (Test-PrefixRevision -Shorter $lastCapturedLine -Longer $Pending) {
                $capturedLines[$capturedLines.Count - 1] = $Pending
                return ($capturedLines -join "`r`n")
            }
        }

        return $text + "`r`n" + $Pending
    }

    return $text
}

function Test-SimilarText {
    param(
        [string]$Left,
        [string]$Right,
        [double]$MaxDistanceRatio = 0.35
    )

    $leftComparison = Get-ComparisonText $Left
    $rightComparison = Get-ComparisonText $Right

    if ([string]::IsNullOrEmpty($leftComparison) -or [string]::IsNullOrEmpty($rightComparison)) {
        return $false
    }

    $maxLength = [Math]::Max($leftComparison.Length, $rightComparison.Length)
    if ($maxLength -eq 0) {
        return $true
    }

    $distance = Get-LevenshteinDistance -Left $leftComparison -Right $rightComparison
    return (($distance / $maxLength) -le $MaxDistanceRatio)
}

function Get-FuzzyOverlapLength {
    param(
        [string]$Existing,
        [string]$Snapshot
    )

    $maxLength = [Math]::Min($Existing.Length, $Snapshot.Length)
    if ($maxLength -lt 20) {
        return 0
    }

    for ($length = $maxLength; $length -ge 20; $length -= 5) {
        $existingTail = $Existing.Substring($Existing.Length - $length)
        $snapshotHead = $Snapshot.Substring(0, $length)

        if ($existingTail -eq $snapshotHead) {
            return $length
        }

        $sampleLength = [Math]::Min(220, $length)
        $tailSample = $existingTail.Substring($existingTail.Length - $sampleLength)
        $headSample = $snapshotHead.Substring(0, $sampleLength)

        if (Test-SimilarText -Left $tailSample -Right $headSample -MaxDistanceRatio 0.22) {
            return $length
        }
    }

    return 0
}

function Merge-CaptionText {
    param(
        [string]$Existing,
        [string]$Snapshot
    )

    $current = Normalize-CaptionText $Snapshot
    if ([string]::IsNullOrWhiteSpace($current)) {
        return $Existing
    }

    if ([string]::IsNullOrEmpty($Existing)) {
        return $current
    }

    if ($current -eq $Existing) {
        return $Existing
    }

    if ($current.StartsWith($Existing)) {
        return $current
    }

    if ($Existing.Contains($current)) {
        return $Existing
    }

    $existingLines = @(
        ($Existing -replace "`r`n|`r|`n", "`n").Split("`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $currentLines = @(
        ($current -replace "`r`n|`r|`n", "`n").Split("`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($existingLines.Count -gt 0 -and $currentLines.Count -eq 1) {
        $lastLineIndex = $existingLines.Count - 1
        $lastLine = $existingLines[$lastLineIndex]
        $currentLine = $currentLines[0]

        if ($lastLine -eq $currentLine) {
            return $Existing
        }

        if (Test-PrefixRevision -Shorter $currentLine -Longer $lastLine) {
            return $Existing
        }

        $lastComparison = Get-ComparisonText $lastLine
        $currentComparison = Get-ComparisonText $currentLine
        $looksLikeRevision = (Test-PrefixRevision -Shorter $lastLine -Longer $currentLine)

        if (-not $looksLikeRevision -and
            $lastComparison.Length -ge 8 -and
            $currentComparison.Length -ge [int]($lastComparison.Length * 0.7)) {
            $looksLikeRevision = Test-SimilarText -Left $lastLine -Right $currentLine -MaxDistanceRatio 0.28
        }

        if ($looksLikeRevision) {
            $existingLines[$lastLineIndex] = $currentLine
            return ($existingLines -join "`r`n")
        }
    }

    $existingStartLength = [Math]::Min(260, $Existing.Length)
    $currentStartLength = [Math]::Min(260, $current.Length)
    $existingStart = $Existing.Substring(0, $existingStartLength)
    $currentStart = $current.Substring(0, $currentStartLength)

    if ($current.Length -ge [int]($Existing.Length * 0.65) -and
        (Test-SimilarText -Left $existingStart -Right $currentStart -MaxDistanceRatio 0.32)) {
        return $current
    }

    $overlapLength = Get-FuzzyOverlapLength -Existing $Existing -Snapshot $current
    if ($overlapLength -gt 0) {
        return $Existing + $current.Substring($overlapLength)
    }

    return $Existing + "`r`n" + $current
}

function Set-ClipboardTextWithRetry {
    param([string]$Text)

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            [System.Windows.Forms.Clipboard]::SetText($Text)
            return $true
        } catch {
            Start-Sleep -Milliseconds 80
        }
    }

    return $false
}

function Paste-TextToNotepad {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$FilePath,
        [string]$Text,
        [switch]$OnlyWhenNotepadIsForeground
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return "pasted"
    }

    if ($OnlyWhenNotepadIsForeground -and -not (Test-NotepadIsForeground -Process $Process -FilePath $FilePath)) {
        return "paused"
    }

    $window = Get-NotepadWindow -Process $Process -FilePath $FilePath
    $oldClipboard = $null
    $hadClipboardText = $false

    try {
        $hadClipboardText = [System.Windows.Forms.Clipboard]::ContainsText()
        if ($hadClipboardText) {
            $oldClipboard = [System.Windows.Forms.Clipboard]::GetText()
        }
    } catch {
    }

    if (-not (Set-ClipboardTextWithRetry -Text $Text)) {
        return "failed"
    }

    if ($OnlyWhenNotepadIsForeground) {
        Focus-NotepadEditor -Window $window | Out-Null
        Start-Sleep -Milliseconds 50
    } else {
        if (-not (Activate-NotepadForPaste -Process $Process -FilePath $FilePath -Window $window)) {
            if ($hadClipboardText) {
                Set-ClipboardTextWithRetry -Text $oldClipboard | Out-Null
            }
            return "failed"
        }
    }

    [System.Windows.Forms.SendKeys]::SendWait("^v")
    Start-Sleep -Milliseconds 50
    [System.Windows.Forms.SendKeys]::SendWait("^s")

    if ($hadClipboardText) {
        Start-Sleep -Milliseconds 50
        Set-ClipboardTextWithRetry -Text $oldClipboard | Out-Null
    }

    return "pasted"
}

function Sync-TextToNotepad {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$FilePath,
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return "pasted"
    }

    if (-not (Test-NotepadIsForeground -Process $Process -FilePath $FilePath)) {
        return "paused"
    }

    $window = Get-NotepadWindow -Process $Process -FilePath $FilePath
    $oldClipboard = $null
    $hadClipboardText = $false

    try {
        $hadClipboardText = [System.Windows.Forms.Clipboard]::ContainsText()
        if ($hadClipboardText) {
            $oldClipboard = [System.Windows.Forms.Clipboard]::GetText()
        }
    } catch {
    }

    if (-not (Set-ClipboardTextWithRetry -Text $Text)) {
        return "failed"
    }

    Focus-NotepadEditor -Window $window | Out-Null
    Start-Sleep -Milliseconds 50
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    Start-Sleep -Milliseconds 40
    [System.Windows.Forms.SendKeys]::SendWait("^v")
    Start-Sleep -Milliseconds 50
    [System.Windows.Forms.SendKeys]::SendWait("^s")

    if ($hadClipboardText) {
        Start-Sleep -Milliseconds 50
        Set-ClipboardTextWithRetry -Text $oldClipboard | Out-Null
    }

    return "pasted"
}

function ConvertFrom-Utf8Base64 {
    param([string]$Value)
    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

$waitingText = ConvertFrom-Utf8Base64 "44OH44K544Kv44OI44OD44OX6Z+z5aOw44KS5b6F44Gj44Gm44GE44G+44GZ4oCm"
$windowTitle = ConvertFrom-Utf8Base64 "5paH5a2X6LW344GT44GX"
$setupText = ConvertFrom-Utf8Base64 "V2luZG93cyDjg6njgqTjg5Yg44Kt44Oj44OX44K344On44Oz44Gu5Yid5pyf6Kit5a6a44KS5a6M5LqG44GX44Gm44GP44Gg44GV44GE"
$startFailureText = ConvertFrom-Utf8Base64 "V2luZG93cyDjg6njgqTjg5Yg44Kt44Oj44OX44K344On44Oz44KS6ZaL5aeL44Gn44GN44G+44Gb44KT"

$backgroundColor = [System.Drawing.Color]::FromArgb(0, 0, 0)
$foregroundColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$form = New-Object System.Windows.Forms.Form
$form.Text = $windowTitle
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.ControlBox = $false
$form.ShowIcon = $false
$form.ShowInTaskbar = $true
$form.TopMost = $false
$form.KeyPreview = $true
$form.BackColor = $backgroundColor
$form.Padding = New-Object System.Windows.Forms.Padding(24, 54, 24, 24)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Opacity = 1.0
$preferredMinimumSize = New-Object System.Drawing.Size(300, 180)
$form.MinimumSize = $preferredMinimumSize

$workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Width = [Math]::Min(1100, [Math]::Max(480, $workingArea.Width - 80))
$form.Height = [Math]::Min(320, [Math]::Max(220, $workingArea.Height - 80))
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Left = $workingArea.Left + [int](($workingArea.Width - $form.Width) / 2)
$form.Top = $workingArea.Bottom - $form.Height - 40

$textDisplay = New-Object System.Windows.Forms.RichTextBox
$textDisplay.Dock = [System.Windows.Forms.DockStyle]::Fill
$textDisplay.ReadOnly = $true
$textDisplay.TabStop = $false
$textDisplay.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$textDisplay.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$textDisplay.WordWrap = $true
$textDisplay.DetectUrls = $false
$textDisplay.BackColor = $backgroundColor
$textDisplay.ForeColor = $foregroundColor
$textDisplay.Font = New-Object System.Drawing.Font("Yu Gothic UI", 24, [System.Drawing.FontStyle]::Regular)
$textDisplay.Text = $waitingText
$form.Controls.Add($textDisplay)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = [string][char]0x00D7
$closeButton.Size = New-Object System.Drawing.Size(44, 40)
$closeButton.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 52), 7)
$closeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$closeButton.TabStop = $false
$closeButton.AccessibleName = "Close"
$closeButton.AccessibleRole = [System.Windows.Forms.AccessibleRole]::PushButton
$closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$closeButton.FlatAppearance.BorderSize = 0
$closeButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(55, 55, 58)
$closeButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(75, 75, 78)
$closeButton.BackColor = $backgroundColor
$closeButton.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$closeButton.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Regular)
$closeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)
$closeButton.BringToFront()
$form.ActiveControl = $null

$resizeBorderThickness = 8

function Get-ResizeHitTestCode {
    param(
        [System.Windows.Forms.Form]$TargetForm,
        [System.Drawing.Point]$Point,
        [int]$BorderThickness
    )

    $isLeft = $Point.X -lt $BorderThickness
    $isRight = $Point.X -ge ($TargetForm.ClientSize.Width - $BorderThickness)
    $isTop = $Point.Y -lt $BorderThickness
    $isBottom = $Point.Y -ge ($TargetForm.ClientSize.Height - $BorderThickness)

    if ($isTop -and $isLeft) { return [NativeWindowTools]::HTTOPLEFT }
    if ($isTop -and $isRight) { return [NativeWindowTools]::HTTOPRIGHT }
    if ($isBottom -and $isLeft) { return [NativeWindowTools]::HTBOTTOMLEFT }
    if ($isBottom -and $isRight) { return [NativeWindowTools]::HTBOTTOMRIGHT }
    if ($isLeft) { return [NativeWindowTools]::HTLEFT }
    if ($isRight) { return [NativeWindowTools]::HTRIGHT }
    if ($isTop) { return [NativeWindowTools]::HTTOP }
    if ($isBottom) { return [NativeWindowTools]::HTBOTTOM }

    return [NativeWindowTools]::HTCAPTION
}

function Test-TextDisplayAtBottom {
    if ($textDisplay.TextLength -eq 0 -or $textDisplay.ClientSize.Height -le 2) {
        return $true
    }

    $bottomPoint = New-Object System.Drawing.Point(1, ($textDisplay.ClientSize.Height - 2))
    $lastVisibleCharacter = $textDisplay.GetCharIndexFromPosition($bottomPoint)
    $lastVisibleLine = $textDisplay.GetLineFromCharIndex($lastVisibleCharacter)
    $lastTextLine = $textDisplay.GetLineFromCharIndex($textDisplay.TextLength)

    return $lastVisibleLine -ge $lastTextLine
}

function Set-TranscriptDisplayText {
    param(
        [string]$Text,
        [switch]$PreserveUserScroll
    )

    if (-not $PreserveUserScroll) {
        $textDisplay.Text = $Text
        return
    }

    $wasAtBottom = (Test-TextDisplayAtBottom) -and $textDisplay.SelectionLength -eq 0
    $scrollY = [NativeWindowTools]::GetRichEditScrollY($textDisplay.Handle)
    $selectionStart = $textDisplay.SelectionStart
    $selectionLength = $textDisplay.SelectionLength

    $textDisplay.Text = $Text

    if ($wasAtBottom) {
        $textDisplay.SelectionStart = $textDisplay.TextLength
        $textDisplay.SelectionLength = 0
        $textDisplay.ScrollToCaret()
        return
    }

    $selectionStart = [Math]::Min($selectionStart, $textDisplay.TextLength)
    $selectionLength = [Math]::Min($selectionLength, $textDisplay.TextLength - $selectionStart)
    $textDisplay.Select($selectionStart, $selectionLength)
    [NativeWindowTools]::SetRichEditScrollY($textDisplay.Handle, $scrollY)
}

$isFullScreen = $false
$windowedBounds = $form.Bounds
$windowedSnapMode = "None"
$snapMode = "None"
$normalBounds = $form.Bounds

function Set-TranscriptWindowBounds {
    param([System.Drawing.Rectangle]$Bounds)

    $followTail = (Test-TextDisplayAtBottom) -and $textDisplay.SelectionLength -eq 0
    $scrollY = [NativeWindowTools]::GetRichEditScrollY($textDisplay.Handle)
    $selectionStart = $textDisplay.SelectionStart
    $selectionLength = $textDisplay.SelectionLength

    $effectiveMinimumWidth = [Math]::Min($script:preferredMinimumSize.Width, [Math]::Max(1, $Bounds.Width))
    $effectiveMinimumHeight = [Math]::Min($script:preferredMinimumSize.Height, [Math]::Max(1, $Bounds.Height))
    $form.MinimumSize = New-Object System.Drawing.Size($effectiveMinimumWidth, $effectiveMinimumHeight)
    $form.Bounds = $Bounds
    $form.PerformLayout()

    if ($followTail) {
        $textDisplay.SelectionStart = $textDisplay.TextLength
        $textDisplay.SelectionLength = 0
        $textDisplay.ScrollToCaret()
        return
    }

    $selectionStart = [Math]::Min($selectionStart, $textDisplay.TextLength)
    $selectionLength = [Math]::Min($selectionLength, $textDisplay.TextLength - $selectionStart)
    $textDisplay.Select($selectionStart, $selectionLength)
    [NativeWindowTools]::SetRichEditScrollY($textDisplay.Handle, $scrollY)
}

function Toggle-FullScreen {

    if (-not $script:isFullScreen) {
        $script:windowedBounds = $form.Bounds
        $script:windowedSnapMode = $script:snapMode
        $script:isFullScreen = $true
        Set-TranscriptWindowBounds -Bounds ([System.Windows.Forms.Screen]::FromControl($form).Bounds)
    } else {
        $script:isFullScreen = $false
        $script:snapMode = $script:windowedSnapMode
        Set-TranscriptWindowBounds -Bounds $script:windowedBounds
    }
}

function Get-WindowSnapTarget {
    param([System.Drawing.Point]$CursorPosition)

    $screen = [System.Windows.Forms.Screen]::FromPoint($CursorPosition)
    $screenBounds = $screen.Bounds
    $dragSize = [System.Windows.Forms.SystemInformation]::DragSize
    $threshold = [Math]::Max(12, [Math]::Max($dragSize.Width, $dragSize.Height) * 2)

    $nearLeft = $CursorPosition.X -le ($screenBounds.Left + $threshold)
    $nearRight = $CursorPosition.X -ge ($screenBounds.Right - 1 - $threshold)
    $nearTop = $CursorPosition.Y -le ($screenBounds.Top + $threshold)
    $nearBottom = $CursorPosition.Y -ge ($screenBounds.Bottom - 1 - $threshold)

    $mode = $null
    if ($nearLeft -and $nearTop) {
        $mode = "TopLeft"
    } elseif ($nearRight -and $nearTop) {
        $mode = "TopRight"
    } elseif ($nearLeft -and $nearBottom) {
        $mode = "BottomLeft"
    } elseif ($nearRight -and $nearBottom) {
        $mode = "BottomRight"
    } elseif ($nearTop) {
        $mode = "Maximized"
    } elseif ($nearLeft) {
        $mode = "Left"
    } elseif ($nearRight) {
        $mode = "Right"
    }

    if ($null -eq $mode) {
        return $null
    }

    return [pscustomobject]@{
        Mode = $mode
        Screen = $screen
        Bounds = Get-WindowSnapBoundsForMode -Screen $screen -Mode $mode
    }
}

function Set-WindowSnapAtCursor {
    param(
        [System.Drawing.Point]$CursorPosition,
        [System.Drawing.Rectangle]$RestoreBounds
    )

    $target = Get-WindowSnapTarget -CursorPosition $CursorPosition
    if ($null -eq $target) {
        return $false
    }

    $normalSourceBounds = if ($script:snapMode -eq "None") { $RestoreBounds } else { $script:normalBounds }
    $normalSourceScreen = [System.Windows.Forms.Screen]::FromRectangle($normalSourceBounds)
    if ($normalSourceScreen.DeviceName -ne $target.Screen.DeviceName) {
        $script:normalBounds = Convert-WindowBoundsToScreen `
            -Bounds $normalSourceBounds `
            -SourceScreen $normalSourceScreen `
            -TargetScreen $target.Screen `
            -MinimumWidth $script:preferredMinimumSize.Width `
            -MinimumHeight $script:preferredMinimumSize.Height
    } elseif ($script:snapMode -eq "None") {
        $script:normalBounds = $RestoreBounds
    }

    $script:snapMode = $target.Mode
    Set-TranscriptWindowBounds -Bounds $target.Bounds
    return $true
}

function Restore-SnappedWindowAtCursor {
    param(
        [System.Drawing.Point]$CursorPosition,
        [double]$HorizontalGrabRatio,
        [int]$HeaderGrabOffset
    )

    if ($script:snapMode -eq "None") {
        return
    }

    $workingArea = [System.Windows.Forms.Screen]::FromPoint($CursorPosition).WorkingArea
    $width = [Math]::Min($script:normalBounds.Width, $workingArea.Width)
    $height = [Math]::Min($script:normalBounds.Height, $workingArea.Height)
    $minimumWidth = [Math]::Min($script:preferredMinimumSize.Width, $workingArea.Width)
    $minimumHeight = [Math]::Min($script:preferredMinimumSize.Height, $workingArea.Height)
    $width = [Math]::Max($minimumWidth, $width)
    $height = [Math]::Max($minimumHeight, $height)
    $HorizontalGrabRatio = [Math]::Max(0.05, [Math]::Min(0.95, $HorizontalGrabRatio))
    $HeaderGrabOffset = [Math]::Max(0, [Math]::Min(($form.Padding.Top - 1), $HeaderGrabOffset))

    $left = $CursorPosition.X - [int][Math]::Round($width * $HorizontalGrabRatio)
    $top = $CursorPosition.Y - $HeaderGrabOffset
    $maximumLeft = [Math]::Max($workingArea.Left, $workingArea.Right - $width)
    $maximumTop = [Math]::Max($workingArea.Top, $workingArea.Bottom - $form.Padding.Top)
    $left = [Math]::Max($workingArea.Left, [Math]::Min($maximumLeft, $left))
    $top = [Math]::Max($workingArea.Top, [Math]::Min($maximumTop, $top))

    $restoredBounds = [System.Drawing.Rectangle]::FromLTRB($left, $top, ($left + $width), ($top + $height))
    $script:snapMode = "None"
    $script:normalBounds = $restoredBounds
    Set-TranscriptWindowBounds -Bounds $restoredBounds
}

function Get-WindowSnapBoundsForWorkingArea {
    param(
        [System.Drawing.Rectangle]$WorkingArea,
        [ValidateSet("Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Maximized")]
        [string]$Mode,
        [int]$MinimumWidth = 1,
        [int]$MinimumHeight = 1
    )

    $leftWidth = [int][Math]::Floor($WorkingArea.Width / 2)
    $rightWidth = $WorkingArea.Width - $leftWidth
    $topHeight = [int][Math]::Floor($WorkingArea.Height / 2)
    $bottomHeight = $WorkingArea.Height - $topHeight
    $middleX = $WorkingArea.Left + $leftWidth
    $middleY = $WorkingArea.Top + $topHeight
    $isPortrait = $WorkingArea.Height -gt $WorkingArea.Width
    $minimumWidth = [Math]::Min([Math]::Max(1, $MinimumWidth), $WorkingArea.Width)
    $minimumHeight = [Math]::Min([Math]::Max(1, $MinimumHeight), $WorkingArea.Height)
    $canSplitWidth = $leftWidth -ge $minimumWidth -and $rightWidth -ge $minimumWidth
    $canSplitHeight = $topHeight -ge $minimumHeight -and $bottomHeight -ge $minimumHeight

    switch ($Mode) {
        "Left" {
            if (-not $canSplitWidth) {
                return $WorkingArea
            }
            return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $WorkingArea.Top, $middleX, $WorkingArea.Bottom)
        }
        "Right" {
            if (-not $canSplitWidth) {
                return $WorkingArea
            }
            return [System.Drawing.Rectangle]::FromLTRB($middleX, $WorkingArea.Top, $WorkingArea.Right, $WorkingArea.Bottom)
        }
        "TopLeft" {
            if ($isPortrait -and $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $WorkingArea.Top, $WorkingArea.Right, $middleY)
            }
            if (-not $canSplitWidth -and $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $WorkingArea.Top, $WorkingArea.Right, $middleY)
            }
            if ($canSplitWidth -and -not $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $WorkingArea.Top, $middleX, $WorkingArea.Bottom)
            }
            if (-not $canSplitWidth -or -not $canSplitHeight) {
                return $WorkingArea
            }
            return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $WorkingArea.Top, $middleX, $middleY)
        }
        "TopRight" {
            if ($isPortrait -and $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $WorkingArea.Top, $WorkingArea.Right, $middleY)
            }
            if (-not $canSplitWidth -and $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $WorkingArea.Top, $WorkingArea.Right, $middleY)
            }
            if ($canSplitWidth -and -not $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($middleX, $WorkingArea.Top, $WorkingArea.Right, $WorkingArea.Bottom)
            }
            if (-not $canSplitWidth -or -not $canSplitHeight) {
                return $WorkingArea
            }
            return [System.Drawing.Rectangle]::FromLTRB($middleX, $WorkingArea.Top, $WorkingArea.Right, $middleY)
        }
        "BottomLeft" {
            if ($isPortrait -and $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $middleY, $WorkingArea.Right, $WorkingArea.Bottom)
            }
            if (-not $canSplitWidth -and $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $middleY, $WorkingArea.Right, $WorkingArea.Bottom)
            }
            if ($canSplitWidth -and -not $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $WorkingArea.Top, $middleX, $WorkingArea.Bottom)
            }
            if (-not $canSplitWidth -or -not $canSplitHeight) {
                return $WorkingArea
            }
            return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $middleY, $middleX, $WorkingArea.Bottom)
        }
        "BottomRight" {
            if ($isPortrait -and $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $middleY, $WorkingArea.Right, $WorkingArea.Bottom)
            }
            if (-not $canSplitWidth -and $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($WorkingArea.Left, $middleY, $WorkingArea.Right, $WorkingArea.Bottom)
            }
            if ($canSplitWidth -and -not $canSplitHeight) {
                return [System.Drawing.Rectangle]::FromLTRB($middleX, $WorkingArea.Top, $WorkingArea.Right, $WorkingArea.Bottom)
            }
            if (-not $canSplitWidth -or -not $canSplitHeight) {
                return $WorkingArea
            }
            return [System.Drawing.Rectangle]::FromLTRB($middleX, $middleY, $WorkingArea.Right, $WorkingArea.Bottom)
        }
        "Maximized" {
            return $WorkingArea
        }
    }
}

function Get-WindowSnapBoundsForMode {
    param(
        [System.Windows.Forms.Screen]$Screen,
        [ValidateSet("Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Maximized")]
        [string]$Mode
    )

    return Get-WindowSnapBoundsForWorkingArea `
        -WorkingArea $Screen.WorkingArea `
        -Mode $Mode `
        -MinimumWidth $script:preferredMinimumSize.Width `
        -MinimumHeight $script:preferredMinimumSize.Height
}

function Get-AdjacentScreen {
    param(
        [System.Windows.Forms.Screen]$CurrentScreen,
        [ValidateSet("Left", "Right", "Up", "Down")]
        [string]$Direction
    )

    $currentBounds = $CurrentScreen.Bounds
    $currentCenterX = $currentBounds.Left + ($currentBounds.Width / 2.0)
    $currentCenterY = $currentBounds.Top + ($currentBounds.Height / 2.0)
    $bestScreen = $null
    $bestScore = [double]::PositiveInfinity

    foreach ($candidate in [System.Windows.Forms.Screen]::AllScreens) {
        if ($candidate.DeviceName -eq $CurrentScreen.DeviceName) {
            continue
        }

        $candidateBounds = $candidate.Bounds
        $candidateCenterX = $candidateBounds.Left + ($candidateBounds.Width / 2.0)
        $candidateCenterY = $candidateBounds.Top + ($candidateBounds.Height / 2.0)
        $isInDirection = $false
        $hasPerpendicularOverlap = $false
        $primaryDistance = 0.0
        $perpendicularGap = 0.0
        $perpendicularCenterDistance = 0.0

        if ($Direction -eq "Left" -or $Direction -eq "Right") {
            $isInDirection = if ($Direction -eq "Left") {
                $candidateCenterX -lt $currentCenterX
            } else {
                $candidateCenterX -gt $currentCenterX
            }
            $hasPerpendicularOverlap = $candidateBounds.Top -lt $currentBounds.Bottom -and
                $candidateBounds.Bottom -gt $currentBounds.Top
            if (-not $hasPerpendicularOverlap) {
                $perpendicularGap = [Math]::Min(
                    [Math]::Abs($candidateBounds.Top - $currentBounds.Bottom),
                    [Math]::Abs($currentBounds.Top - $candidateBounds.Bottom)
                )
            }
            $primaryDistance = [Math]::Abs($candidateCenterX - $currentCenterX)
            $perpendicularCenterDistance = [Math]::Abs($candidateCenterY - $currentCenterY)
        } else {
            $isInDirection = if ($Direction -eq "Up") {
                $candidateCenterY -lt $currentCenterY
            } else {
                $candidateCenterY -gt $currentCenterY
            }
            $hasPerpendicularOverlap = $candidateBounds.Left -lt $currentBounds.Right -and
                $candidateBounds.Right -gt $currentBounds.Left
            if (-not $hasPerpendicularOverlap) {
                $perpendicularGap = [Math]::Min(
                    [Math]::Abs($candidateBounds.Left - $currentBounds.Right),
                    [Math]::Abs($currentBounds.Left - $candidateBounds.Right)
                )
            }
            $primaryDistance = [Math]::Abs($candidateCenterY - $currentCenterY)
            $perpendicularCenterDistance = [Math]::Abs($candidateCenterX - $currentCenterX)
        }

        if (-not $isInDirection) {
            continue
        }

        $overlapPenalty = if ($hasPerpendicularOverlap) { 0.0 } else { 1000000000000.0 }
        $score = $overlapPenalty +
            ($primaryDistance * 1000000.0) +
            ($perpendicularGap * 1000.0) +
            $perpendicularCenterDistance

        if ($score -lt $bestScore -or
            ($score -eq $bestScore -and $null -ne $bestScreen -and
                [string]::CompareOrdinal($candidate.DeviceName, $bestScreen.DeviceName) -lt 0)) {
            $bestScore = $score
            $bestScreen = $candidate
        }
    }

    return $bestScreen
}

function Convert-WindowBoundsToScreen {
    param(
        [System.Drawing.Rectangle]$Bounds,
        [System.Windows.Forms.Screen]$SourceScreen,
        [System.Windows.Forms.Screen]$TargetScreen,
        [int]$MinimumWidth = 1,
        [int]$MinimumHeight = 1
    )

    $sourceArea = $SourceScreen.WorkingArea
    $targetArea = $TargetScreen.WorkingArea
    $minimumWidth = [Math]::Min([Math]::Max(1, $MinimumWidth), $targetArea.Width)
    $minimumHeight = [Math]::Min([Math]::Max(1, $MinimumHeight), $targetArea.Height)
    $width = [Math]::Min([Math]::Max($minimumWidth, $Bounds.Width), $targetArea.Width)
    $height = [Math]::Min([Math]::Max($minimumHeight, $Bounds.Height), $targetArea.Height)

    $sourceWidth = [Math]::Min([Math]::Max(1, $Bounds.Width), $sourceArea.Width)
    $sourceHeight = [Math]::Min([Math]::Max(1, $Bounds.Height), $sourceArea.Height)
    $sourceTravelX = [Math]::Max(0, $sourceArea.Width - $sourceWidth)
    $sourceTravelY = [Math]::Max(0, $sourceArea.Height - $sourceHeight)
    $ratioX = if ($sourceTravelX -gt 0) {
        ($Bounds.Left - $sourceArea.Left) / [double]$sourceTravelX
    } else {
        0.5
    }
    $ratioY = if ($sourceTravelY -gt 0) {
        ($Bounds.Top - $sourceArea.Top) / [double]$sourceTravelY
    } else {
        0.5
    }
    $ratioX = [Math]::Max(0.0, [Math]::Min(1.0, $ratioX))
    $ratioY = [Math]::Max(0.0, [Math]::Min(1.0, $ratioY))

    $targetTravelX = [Math]::Max(0, $targetArea.Width - $width)
    $targetTravelY = [Math]::Max(0, $targetArea.Height - $height)
    $left = $targetArea.Left + [int][Math]::Round($targetTravelX * $ratioX)
    $top = $targetArea.Top + [int][Math]::Round($targetTravelY * $ratioY)

    return [System.Drawing.Rectangle]::FromLTRB($left, $top, ($left + $width), ($top + $height))
}

function Move-TranscriptWindowToScreen {
    param(
        [System.Windows.Forms.Screen]$TargetScreen,
        [System.Drawing.Rectangle]$SourceBounds,
        [ValidateSet("None", "Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Maximized")]
        [string]$Mode
    )

    $sourceScreen = [System.Windows.Forms.Screen]::FromRectangle($SourceBounds)
    if ($sourceScreen.DeviceName -eq $TargetScreen.DeviceName) {
        return $false
    }

    $normalSourceScreen = [System.Windows.Forms.Screen]::FromRectangle($script:normalBounds)
    $translatedNormalBounds = Convert-WindowBoundsToScreen `
        -Bounds $script:normalBounds `
        -SourceScreen $normalSourceScreen `
        -TargetScreen $TargetScreen `
        -MinimumWidth $script:preferredMinimumSize.Width `
        -MinimumHeight $script:preferredMinimumSize.Height

    if ($script:isFullScreen) {
        if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        $windowedSourceScreen = [System.Windows.Forms.Screen]::FromRectangle($script:windowedBounds)
        if ($script:windowedSnapMode -eq "None") {
            $script:windowedBounds = Convert-WindowBoundsToScreen `
                -Bounds $script:windowedBounds `
                -SourceScreen $windowedSourceScreen `
                -TargetScreen $TargetScreen `
                -MinimumWidth $script:preferredMinimumSize.Width `
                -MinimumHeight $script:preferredMinimumSize.Height
        } else {
            $script:windowedSnapMode = $Mode
            $script:snapMode = $Mode
            $script:windowedBounds = Get-WindowSnapBoundsForMode -Screen $TargetScreen -Mode $Mode
        }
        $script:normalBounds = $translatedNormalBounds
        Set-TranscriptWindowBounds -Bounds $TargetScreen.Bounds
        return $true
    }

    if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }

    if ($Mode -eq "None") {
        $movedBounds = Convert-WindowBoundsToScreen `
            -Bounds $SourceBounds `
            -SourceScreen $sourceScreen `
            -TargetScreen $TargetScreen `
            -MinimumWidth $script:preferredMinimumSize.Width `
            -MinimumHeight $script:preferredMinimumSize.Height
        $script:snapMode = "None"
        $script:normalBounds = $movedBounds
        Set-TranscriptWindowBounds -Bounds $movedBounds
    } else {
        $script:normalBounds = $translatedNormalBounds
        $script:snapMode = $Mode
        Set-TranscriptWindowBounds -Bounds (Get-WindowSnapBoundsForMode -Screen $TargetScreen -Mode $Mode)
    }

    return $true
}

function Move-WindowToAdjacentScreen {
    param(
        [ValidateSet("Left", "Right")]
        [string]$Direction,
        [System.Drawing.Rectangle]$SourceBounds,
        [ValidateSet("None", "Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Maximized")]
        [string]$Mode
    )

    $sourceScreen = [System.Windows.Forms.Screen]::FromRectangle($SourceBounds)
    $targetScreen = Get-AdjacentScreen -CurrentScreen $sourceScreen -Direction $Direction
    if ($null -eq $targetScreen) {
        return $false
    }

    return Move-TranscriptWindowToScreen -TargetScreen $targetScreen -SourceBounds $SourceBounds -Mode $Mode
}

function Set-WindowSnapMode {
    param(
        [ValidateSet("Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Maximized")]
        [string]$Mode,
        [System.Windows.Forms.Screen]$Screen = [System.Windows.Forms.Screen]::FromRectangle($form.Bounds),
        [System.Drawing.Rectangle]$RestoreBounds = [System.Drawing.Rectangle]::Empty
    )

    if ($script:isFullScreen) {
        Toggle-FullScreen
    }
    if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }
    if ($script:snapMode -eq "None") {
        $script:normalBounds = if ($RestoreBounds.IsEmpty) { $form.Bounds } else { $RestoreBounds }
    }

    $script:snapMode = $Mode
    Set-TranscriptWindowBounds -Bounds (Get-WindowSnapBoundsForMode -Screen $Screen -Mode $Mode)
}

function Restore-WindowFromSnap {
    if ($script:snapMode -eq "None") {
        return
    }

    if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }
    $restoreBounds = $script:normalBounds
    $script:snapMode = "None"
    Set-TranscriptWindowBounds -Bounds $restoreBounds
}

function Get-SnapModeForAdjacentScreenMove {
    param(
        [ValidateSet("None", "Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Maximized")]
        [string]$Mode,
        [ValidateSet("Left", "Right")]
        [string]$Direction,
        [bool]$SourceIsPortrait
    )

    if (-not $SourceIsPortrait) {
        return $Mode
    }
    if ($Mode -eq "TopLeft" -or $Mode -eq "TopRight") {
        if ($Direction -eq "Left") {
            return "TopRight"
        }
        return "TopLeft"
    }
    if ($Mode -eq "BottomLeft" -or $Mode -eq "BottomRight") {
        if ($Direction -eq "Left") {
            return "BottomRight"
        }
        return "BottomLeft"
    }
    return $Mode
}

function Get-HorizontalWinArrowAction {
    param(
        [ValidateSet("None", "Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Maximized")]
        [string]$Mode,
        [ValidateSet("Left", "Right")]
        [string]$Direction,
        [bool]$IsPortrait = $false,
        [bool]$CanSplitHorizontally = $true
    )

    if (-not $CanSplitHorizontally -and ($Mode -eq "Left" -or $Mode -eq "Right")) {
        $targetMode = if ($Direction -eq "Left") { "Right" } else { "Left" }
        return [pscustomobject]@{ MoveToAdjacentScreen = $true; TargetMode = $targetMode }
    }
    if ($IsPortrait -and ($Mode -eq "TopLeft" -or $Mode -eq "TopRight")) {
        $targetMode = if ($Direction -eq "Left") { "TopRight" } else { "TopLeft" }
        return [pscustomobject]@{ MoveToAdjacentScreen = $true; TargetMode = $targetMode }
    }
    if ($IsPortrait -and ($Mode -eq "BottomLeft" -or $Mode -eq "BottomRight")) {
        $targetMode = if ($Direction -eq "Left") { "BottomRight" } else { "BottomLeft" }
        return [pscustomobject]@{ MoveToAdjacentScreen = $true; TargetMode = $targetMode }
    }

    if ($Direction -eq "Left") {
        switch ($Mode) {
            "Left" {
                return [pscustomobject]@{ MoveToAdjacentScreen = $true; TargetMode = "Right" }
            }
            "TopLeft" {
                return [pscustomobject]@{ MoveToAdjacentScreen = $true; TargetMode = "TopRight" }
            }
            "BottomLeft" {
                return [pscustomobject]@{ MoveToAdjacentScreen = $true; TargetMode = "BottomRight" }
            }
            "TopRight" { return [pscustomobject]@{ MoveToAdjacentScreen = $false; TargetMode = "TopLeft" } }
            "BottomRight" { return [pscustomobject]@{ MoveToAdjacentScreen = $false; TargetMode = "BottomLeft" } }
            default { return [pscustomobject]@{ MoveToAdjacentScreen = $false; TargetMode = "Left" } }
        }
    }

    switch ($Mode) {
        "Right" {
            return [pscustomobject]@{ MoveToAdjacentScreen = $true; TargetMode = "Left" }
        }
        "TopRight" {
            return [pscustomobject]@{ MoveToAdjacentScreen = $true; TargetMode = "TopLeft" }
        }
        "BottomRight" {
            return [pscustomobject]@{ MoveToAdjacentScreen = $true; TargetMode = "BottomLeft" }
        }
        "TopLeft" { return [pscustomobject]@{ MoveToAdjacentScreen = $false; TargetMode = "TopRight" } }
        "BottomLeft" { return [pscustomobject]@{ MoveToAdjacentScreen = $false; TargetMode = "BottomRight" } }
        default { return [pscustomobject]@{ MoveToAdjacentScreen = $false; TargetMode = "Right" } }
    }
}

function Invoke-HorizontalWinArrowShortcut {
    param(
        [int]$VirtualKey,
        [System.Drawing.Rectangle]$SourceBounds
    )

    $direction = if ($VirtualKey -eq [ForegroundWinArrowMonitor]::VK_LEFT) { "Left" } else { "Right" }
    $screen = [System.Windows.Forms.Screen]::FromRectangle($SourceBounds)
    $currentMode = $script:snapMode
    $isPortrait = $screen.WorkingArea.Height -gt $screen.WorkingArea.Width
    $leftWidth = [int][Math]::Floor($screen.WorkingArea.Width / 2)
    $rightWidth = $screen.WorkingArea.Width - $leftWidth
    $canSplitHorizontally = $leftWidth -ge $script:preferredMinimumSize.Width -and
        $rightWidth -ge $script:preferredMinimumSize.Width
    $action = Get-HorizontalWinArrowAction `
        -Mode $currentMode `
        -Direction $direction `
        -IsPortrait $isPortrait `
        -CanSplitHorizontally $canSplitHorizontally

    if ($action.MoveToAdjacentScreen) {
        if (-not (Move-WindowToAdjacentScreen `
                -Direction $direction `
                -SourceBounds $SourceBounds `
                -Mode $action.TargetMode)) {
            Set-WindowSnapMode -Mode $currentMode -Screen $screen -RestoreBounds $SourceBounds
        }
    } else {
        Set-WindowSnapMode -Mode $action.TargetMode -Screen $screen -RestoreBounds $SourceBounds
    }
}

function Invoke-WinArrowShortcut {
    param(
        [int]$VirtualKey,
        [System.Drawing.Rectangle]$SourceBounds,
        [switch]$MoveToOtherScreen
    )

    if ($script:formClosed -or $form.IsDisposed) {
        return
    }

    if ($MoveToOtherScreen) {
        $direction = if ($VirtualKey -eq [ForegroundWinArrowMonitor]::VK_LEFT) { "Left" } else { "Right" }
        $sourceScreen = [System.Windows.Forms.Screen]::FromRectangle($SourceBounds)
        $sourceIsPortrait = $sourceScreen.WorkingArea.Height -gt $sourceScreen.WorkingArea.Width
        $targetMode = Get-SnapModeForAdjacentScreenMove `
            -Mode $script:snapMode `
            -Direction $direction `
            -SourceIsPortrait $sourceIsPortrait
        $moved = Move-WindowToAdjacentScreen `
            -Direction $direction `
            -SourceBounds $SourceBounds `
            -Mode $targetMode
        if (-not $moved) {
            if ($script:isFullScreen) {
                if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
                    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
                }
                Set-TranscriptWindowBounds -Bounds $sourceScreen.Bounds
            } elseif ($script:snapMode -eq "None") {
                if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
                    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
                }
                Set-TranscriptWindowBounds -Bounds $SourceBounds
            } else {
                if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
                    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
                }
                Set-TranscriptWindowBounds -Bounds (Get-WindowSnapBoundsForMode -Screen $sourceScreen -Mode $script:snapMode)
            }
        }
        return
    }

    if ($script:isFullScreen) {
        $sourceScreen = [System.Windows.Forms.Screen]::FromRectangle($SourceBounds)
        if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        if ($VirtualKey -eq [ForegroundWinArrowMonitor]::VK_UP) {
            Set-TranscriptWindowBounds -Bounds $sourceScreen.Bounds
            return
        }
        Toggle-FullScreen
        if ($VirtualKey -eq [ForegroundWinArrowMonitor]::VK_DOWN) {
            return
        }
        $SourceBounds = $form.Bounds
    }

    $screen = [System.Windows.Forms.Screen]::FromRectangle($SourceBounds)
    switch ($VirtualKey) {
        ([ForegroundWinArrowMonitor]::VK_LEFT) {
            Invoke-HorizontalWinArrowShortcut -VirtualKey $VirtualKey -SourceBounds $SourceBounds
        }
        ([ForegroundWinArrowMonitor]::VK_RIGHT) {
            Invoke-HorizontalWinArrowShortcut -VirtualKey $VirtualKey -SourceBounds $SourceBounds
        }
        ([ForegroundWinArrowMonitor]::VK_UP) {
            switch ($script:snapMode) {
                "Left" { Set-WindowSnapMode -Mode "TopLeft" -Screen $screen -RestoreBounds $SourceBounds }
                "BottomLeft" { Set-WindowSnapMode -Mode "TopLeft" -Screen $screen -RestoreBounds $SourceBounds }
                "Right" { Set-WindowSnapMode -Mode "TopRight" -Screen $screen -RestoreBounds $SourceBounds }
                "BottomRight" { Set-WindowSnapMode -Mode "TopRight" -Screen $screen -RestoreBounds $SourceBounds }
                "TopLeft" { Set-WindowSnapMode -Mode "Maximized" -Screen $screen -RestoreBounds $SourceBounds }
                "TopRight" { Set-WindowSnapMode -Mode "Maximized" -Screen $screen -RestoreBounds $SourceBounds }
                "Maximized" { Set-WindowSnapMode -Mode "Maximized" -Screen $screen -RestoreBounds $SourceBounds }
                default { Set-WindowSnapMode -Mode "Maximized" -Screen $screen -RestoreBounds $SourceBounds }
            }
        }
        ([ForegroundWinArrowMonitor]::VK_DOWN) {
            switch ($script:snapMode) {
                "Maximized" { Restore-WindowFromSnap }
                "TopLeft" { Set-WindowSnapMode -Mode "BottomLeft" -Screen $screen -RestoreBounds $SourceBounds }
                "Left" { Set-WindowSnapMode -Mode "BottomLeft" -Screen $screen -RestoreBounds $SourceBounds }
                "TopRight" { Set-WindowSnapMode -Mode "BottomRight" -Screen $screen -RestoreBounds $SourceBounds }
                "Right" { Set-WindowSnapMode -Mode "BottomRight" -Screen $screen -RestoreBounds $SourceBounds }
                "BottomLeft" { Restore-WindowFromSnap }
                "BottomRight" { Restore-WindowFromSnap }
                default { $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized }
            }
        }
    }
}

function Invoke-PendingWinArrowShortcuts {
    $processedCommand = $false
    while ($true) {
        $command = [ForegroundWinArrowMonitor]::TakePendingKey()
        if ($null -eq $command) {
            return
        }
        try {
            $sourceBounds = if ($processedCommand) {
                $form.Bounds
            } else {
                [System.Drawing.Rectangle]::FromLTRB(
                    $command.WindowLeft,
                    $command.WindowTop,
                    $command.WindowRight,
                    $command.WindowBottom
                )
            }
            Invoke-WinArrowShortcut `
                -VirtualKey $command.VirtualKey `
                -SourceBounds $sourceBounds `
                -MoveToOtherScreen:$command.ShiftPressed
            $processedCommand = $true
        } catch {
        }
    }
}

$formClosed = $false
$followTailAfterResize = $false
$f11Held = $false
$winArrowMonitorInstalled = $false
$form.Add_FormClosed({ $script:formClosed = $true })
$form.Add_ResizeBegin({
    $script:followTailAfterResize = (Test-TextDisplayAtBottom) -and $textDisplay.SelectionLength -eq 0
})
$form.Add_ResizeEnd({
    if ($script:followTailAfterResize) {
        $textDisplay.SelectionStart = $textDisplay.TextLength
        $textDisplay.SelectionLength = 0
        $textDisplay.ScrollToCaret()
    }
    $script:followTailAfterResize = $false
})
$handleWindowKeys = {
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $eventArgs.Handled = $true
        $eventArgs.SuppressKeyPress = $true
        $form.Close()
    } elseif ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F11) {
        $eventArgs.Handled = $true
        if (-not $script:f11Held) {
            $script:f11Held = $true
            Toggle-FullScreen
        }
    }
}
$releaseWindowKeys = {
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F11) {
        $script:f11Held = $false
        $eventArgs.Handled = $true
        $eventArgs.SuppressKeyPress = $true
    }
}
$form.Add_KeyDown($handleWindowKeys)
$form.Add_KeyUp($releaseWindowKeys)
$textDisplay.Add_PreviewKeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape -or
        $eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F11) {
        $eventArgs.IsInputKey = $true
    }
})
$textDisplay.Add_KeyDown($handleWindowKeys)
$textDisplay.Add_KeyUp($releaseWindowKeys)
$form.Add_MouseMove({
    param($sender, $eventArgs)

    if ($script:isFullScreen -or
        $eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::None) {
        $sender.Cursor = [System.Windows.Forms.Cursors]::Default
        return
    }

    $hitTest = Get-ResizeHitTestCode -TargetForm $sender -Point $eventArgs.Location -BorderThickness $resizeBorderThickness
    if ($hitTest -eq [NativeWindowTools]::HTLEFT -or $hitTest -eq [NativeWindowTools]::HTRIGHT) {
        $sender.Cursor = [System.Windows.Forms.Cursors]::SizeWE
    } elseif ($hitTest -eq [NativeWindowTools]::HTTOP -or $hitTest -eq [NativeWindowTools]::HTBOTTOM) {
        $sender.Cursor = [System.Windows.Forms.Cursors]::SizeNS
    } elseif ($hitTest -eq [NativeWindowTools]::HTTOPLEFT -or $hitTest -eq [NativeWindowTools]::HTBOTTOMRIGHT) {
        $sender.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE
    } elseif ($hitTest -eq [NativeWindowTools]::HTTOPRIGHT -or $hitTest -eq [NativeWindowTools]::HTBOTTOMLEFT) {
        $sender.Cursor = [System.Windows.Forms.Cursors]::SizeNESW
    } else {
        $sender.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})
$form.Add_MouseLeave({
    param($sender, $eventArgs)
    $sender.Cursor = [System.Windows.Forms.Cursors]::Default
})
$form.Add_MouseDown({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $hitTest = Get-ResizeHitTestCode -TargetForm $sender -Point $eventArgs.Location -BorderThickness $resizeBorderThickness
        $isTopMarginDoubleClick = (
            $eventArgs.Clicks -ge 2 -and
            $eventArgs.Y -lt $form.Padding.Top -and
            $hitTest -eq [NativeWindowTools]::HTCAPTION
        )
        if ($isTopMarginDoubleClick) {
            Toggle-FullScreen
            return
        }
        if ($script:isFullScreen) {
            return
        }

        $dragStartPoint = [System.Windows.Forms.Cursor]::Position
        $boundsBeforeMove = $form.Bounds
        $snapModeBeforeMove = $script:snapMode
        $horizontalGrabRatio = $eventArgs.X / [Math]::Max(1, $form.ClientSize.Width)
        $headerGrabOffset = $eventArgs.Y
        [NativeWindowTools]::ReleaseCapture() | Out-Null
        [NativeWindowTools]::SendMessage(
            $sender.Handle,
            [NativeWindowTools]::WM_NCLBUTTONDOWN,
            [IntPtr]$hitTest,
            [IntPtr]::Zero
        ) | Out-Null

        $nativeBounds = New-Object NativeWindowTools+NativeRect
        $hasNativeBounds = [NativeWindowTools]::GetWindowRect($sender.Handle, [ref]$nativeBounds)
        $boundsAfterOperation = if ($hasNativeBounds) {
            [System.Drawing.Rectangle]::FromLTRB(
                $nativeBounds.Left,
                $nativeBounds.Top,
                $nativeBounds.Right,
                $nativeBounds.Bottom
            )
        } else {
            $form.Bounds
        }
        $boundsChanged = -not $boundsAfterOperation.Equals($boundsBeforeMove)

        if ($hitTest -ne [NativeWindowTools]::HTCAPTION) {
            $resizeEndPoint = [System.Windows.Forms.Cursor]::Position
            $resizeDragSize = [System.Windows.Forms.SystemInformation]::DragSize
            $wasResized = (
                [Math]::Abs($resizeEndPoint.X - $dragStartPoint.X) -ge [Math]::Max(1, [int][Math]::Ceiling($resizeDragSize.Width / 2)) -or
                [Math]::Abs($resizeEndPoint.Y - $dragStartPoint.Y) -ge [Math]::Max(1, [int][Math]::Ceiling($resizeDragSize.Height / 2))
            )
            if ($wasResized -and $boundsChanged) {
                $script:snapMode = "None"
                $script:normalBounds = $boundsAfterOperation
            }
            return
        }

        $dropPoint = [System.Windows.Forms.Cursor]::Position
        $dragSize = [System.Windows.Forms.SystemInformation]::DragSize
        $minimumX = [Math]::Max(1, [int][Math]::Ceiling($dragSize.Width / 2))
        $minimumY = [Math]::Max(1, [int][Math]::Ceiling($dragSize.Height / 2))
        $draggedFarEnough = (
            [Math]::Abs($dropPoint.X - $dragStartPoint.X) -ge $minimumX -or
            [Math]::Abs($dropPoint.Y - $dragStartPoint.Y) -ge $minimumY
        )
        if (-not $draggedFarEnough -or -not $boundsChanged) {
            return
        }

        $didSnap = Set-WindowSnapAtCursor -CursorPosition $dropPoint -RestoreBounds $boundsBeforeMove
        if ($didSnap) {
            return
        }

        if ($snapModeBeforeMove -ne "None") {
            Restore-SnappedWindowAtCursor `
                -CursorPosition $dropPoint `
                -HorizontalGrabRatio $horizontalGrabRatio `
                -HeaderGrabOffset $headerGrabOffset
        } else {
            $script:snapMode = "None"
            $script:normalBounds = $form.Bounds
        }
    }
})
$form.Show()
$form.Activate()
$winArrowMonitorInstalled = [ForegroundWinArrowMonitor]::Install($form.Handle)

$ownedLiveCaptionsProcessId = 0
$lastLiveCaptionsStartAttempt = [DateTime]::MinValue
Close-LiveCaptions
Send-LiveCaptionsShortcut
$lastLiveCaptionsStartAttempt = Get-Date

$lastSnapshot = ""
$capturedText = ""
$pendingCaptionText = ""
$lastDisplayedText = ""
$liveCaptionsMovedOffScreen = $false
$hasActivatedTranscriptWindow = $false

function Save-CapturedText {
    param([string]$Text)

    [System.IO.File]::WriteAllText($transcriptPath, $Text, [System.Text.Encoding]::UTF8)
}

function Add-CapturedCaptionLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $false
    }

    $mergedText = Merge-CaptionText -Existing $script:capturedText -Snapshot $Line

    if ($mergedText -ne $script:capturedText) {
        $script:capturedText = $mergedText
        return $true
    }

    return $false
}

function Test-PendingCaptionSupersededByLine {
    param(
        [string]$Pending,
        [string]$Line
    )

    if ([string]::IsNullOrWhiteSpace($Pending) -or [string]::IsNullOrWhiteSpace($Line)) {
        return $false
    }

    if ($Pending -eq $Line) {
        return $true
    }

    if (Test-PrefixRevision -Shorter $Pending -Longer $Line) {
        return $true
    }

    $pendingComparison = Get-ComparisonText $Pending
    $lineComparison = Get-ComparisonText $Line

    if ($pendingComparison.Length -lt 8 -or $lineComparison.Length -lt [int]($pendingComparison.Length * 0.6)) {
        return $false
    }

    return (Test-SimilarText -Left $Pending -Right $Line -MaxDistanceRatio 0.34)
}

function Flush-PendingCaptionText {
    if ([string]::IsNullOrWhiteSpace($script:pendingCaptionText)) {
        return $false
    }

    if (-not (Test-RescuableCaptionLine $script:pendingCaptionText)) {
        $script:pendingCaptionText = ""
        return $false
    }

    $changed = Add-CapturedCaptionLine -Line $script:pendingCaptionText
    $script:pendingCaptionText = ""
    return $changed
}

function Set-PendingCaptionTextSafely {
    param([string]$Text)

    $newPending = Normalize-CaptionText $Text
    if ([string]::IsNullOrWhiteSpace($newPending)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($script:pendingCaptionText)) {
        $script:pendingCaptionText = $newPending
        return $false
    }

    if (Test-PendingCaptionSupersededByLine -Pending $script:pendingCaptionText -Line $newPending) {
        $script:pendingCaptionText = $newPending
        return $false
    }

    if (Test-PendingCaptionSupersededByLine -Pending $newPending -Line $script:pendingCaptionText) {
        return $false
    }

    $changed = Flush-PendingCaptionText
    $script:pendingCaptionText = $newPending
    return $changed
}

function Resolve-PendingCaptionBeforeCapturedLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($script:pendingCaptionText)) {
        return $false
    }

    if (Test-PendingCaptionSupersededByLine -Pending $script:pendingCaptionText -Line $Line) {
        $script:pendingCaptionText = ""
        return $false
    }

    return (Flush-PendingCaptionText)
}

try {
    while (-not $formClosed -and -not $form.IsDisposed) {
        [System.Windows.Forms.Application]::DoEvents()
        Invoke-PendingWinArrowShortcuts
        if ($formClosed -or $form.IsDisposed) {
            break
        }

        $liveCaptionsWindow = Get-LiveCaptionsWindow
        if ($null -eq $liveCaptionsWindow) {
            $liveCaptionsMovedOffScreen = $false
            $liveCaptionsProcess = Get-Process -Name "LiveCaptions" -ErrorAction SilentlyContinue
            if ($ownedLiveCaptionsProcessId -gt 0 -and
                $null -eq (Get-Process -Id $ownedLiveCaptionsProcessId -ErrorAction SilentlyContinue)) {
                $ownedLiveCaptionsProcessId = 0
            }
            if ($ownedLiveCaptionsProcessId -eq 0 -and $null -ne $liveCaptionsProcess) {
                $ownedLiveCaptionsProcessId = [int](@($liveCaptionsProcess)[0].Id)
            }
            $secondsSinceStartAttempt = ((Get-Date) - $lastLiveCaptionsStartAttempt).TotalSeconds

            if ($null -eq $liveCaptionsProcess -and $secondsSinceStartAttempt -ge 5) {
                Send-LiveCaptionsShortcut
                $lastLiveCaptionsStartAttempt = Get-Date
                $secondsSinceStartAttempt = 0
            }

            $statusText = $waitingText
            if ($secondsSinceStartAttempt -ge 10) {
                $statusText = $startFailureText
            }
            if ([string]::IsNullOrWhiteSpace($capturedText) -and $lastDisplayedText -ne $statusText) {
                $textDisplay.Text = $statusText
                $lastDisplayedText = $statusText
            }

            Start-Sleep -Milliseconds $PollMilliseconds
            continue
        }

        if ($ownedLiveCaptionsProcessId -eq 0) {
            try {
                $ownedLiveCaptionsProcessId = [int]$liveCaptionsWindow.Current.ProcessId
            } catch {
            }
        }

        if (-not (Test-LiveCaptionsReadyForBackground -Window $liveCaptionsWindow)) {
            if ([string]::IsNullOrWhiteSpace($capturedText) -and $lastDisplayedText -ne $setupText) {
                $textDisplay.Text = $setupText
                $lastDisplayedText = $setupText
            }
            Start-Sleep -Milliseconds $PollMilliseconds
            continue
        }

        Move-LiveCaptionsOffScreen -Window $liveCaptionsWindow
        if (-not $liveCaptionsMovedOffScreen) {
            if (-not $hasActivatedTranscriptWindow) {
                $form.Activate()
                [NativeWindowTools]::SetForegroundWindow($form.Handle) | Out-Null
                if ([string]::IsNullOrWhiteSpace($capturedText) -and
                    [string]::IsNullOrWhiteSpace($pendingCaptionText)) {
                    $textDisplay.SelectionStart = 0
                    $textDisplay.SelectionLength = 0
                    $textDisplay.ScrollToCaret()
                }
                $form.ActiveControl = $null
                $form.Focus() | Out-Null
                $hasActivatedTranscriptWindow = $true
            }
            $liveCaptionsMovedOffScreen = $true
        }
        $snapshot = Get-LiveCaptionSnapshot -Window $liveCaptionsWindow

        if ([string]::IsNullOrWhiteSpace($snapshot)) {
            if ([string]::IsNullOrWhiteSpace($capturedText) -and $lastDisplayedText -ne $waitingText) {
                $textDisplay.Text = $waitingText
                $lastDisplayedText = $waitingText
            }
            Start-Sleep -Milliseconds $PollMilliseconds
            continue
        }

        $snapshotLines = @(Split-CaptionLines $snapshot)
        if ($snapshotLines.Count -eq 0) {
            Start-Sleep -Milliseconds $PollMilliseconds
            continue
        }

        for ($lineIndex = 0; $lineIndex -lt ($snapshotLines.Count - 1); $lineIndex++) {
            Add-CapturedCaptionLine -Line $snapshotLines[$lineIndex] | Out-Null
        }

        $pendingCaptionText = Normalize-CaptionText $snapshotLines[$snapshotLines.Count - 1]

        $displayText = Get-TranscriptText -Captured $capturedText -Pending $pendingCaptionText -IncludePending
        if (-not [string]::IsNullOrWhiteSpace($displayText) -and $displayText -ne $lastDisplayedText) {
            Save-CapturedText -Text $displayText
            Set-TranscriptDisplayText -Text $displayText -PreserveUserScroll
            $lastDisplayedText = $displayText
        }

        $lastSnapshot = $snapshot
        Start-Sleep -Milliseconds $PollMilliseconds
    }
} finally {
    try {
        [ForegroundWinArrowMonitor]::Uninstall()
        $winArrowMonitorInstalled = $false
    } catch {
    }

    try {
        Flush-PendingCaptionText | Out-Null
        $finalText = Get-TranscriptText -Captured $capturedText -Pending $pendingCaptionText -IncludePending
        Save-CapturedText -Text $finalText
    } catch {
    }

    try {
        if ($ownedLiveCaptionsProcessId -gt 0) {
            Close-LiveCaptions -ProcessId $ownedLiveCaptionsProcessId
        }
    } catch {
    }

    try {
        if ($null -ne $form -and -not $form.IsDisposed) {
            $form.Close()
            $form.Dispose()
        }
    } catch {
    }

    if ($createdNewInstance -and $null -ne $instanceMutex) {
        try {
            $instanceMutex.ReleaseMutex()
        } catch {
        }
        try {
            $instanceMutex.Dispose()
        } catch {
        }
    }
}
