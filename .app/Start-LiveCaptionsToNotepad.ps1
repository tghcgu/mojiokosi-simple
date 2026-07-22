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
        $fileNam…15584 tokens truncated…  -Direction $direction `
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
