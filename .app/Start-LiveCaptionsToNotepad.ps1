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

Add-Type -ReferencedAssemblies "System.Windows.Forms" -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public static class NativeWindowTools
{
    [StructLayout(LayoutKind.Sequential)]
    private struct ScrollInfo
    {
        public uint Size;
        public uint Mask;
        public int Minimum;
        public int Maximum;
        public uint PageSize;
        public int Position;
        public int TrackPosition;
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
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

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

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetScrollInfo(IntPtr hWnd, int scrollBar, ref ScrollInfo scrollInfo);

    public static bool IsRichEditAtBottom(IntPtr hWnd)
    {
        if (hWnd == IntPtr.Zero)
        {
            return true;
        }

        ScrollInfo info = new ScrollInfo();
        info.Size = (uint)Marshal.SizeOf(typeof(ScrollInfo));
        info.Mask = SIF_RANGE | SIF_PAGE | SIF_POS;
        if (!GetScrollInfo(hWnd, SB_VERT, ref info))
        {
            return true;
        }

        int pageSize = info.PageSize > Int32.MaxValue ? Int32.MaxValue : (int)info.PageSize;
        int maximumPosition = Math.Max(
            info.Minimum,
            info.Maximum - Math.Max(pageSize - 1, 0)
        );
        return info.Position >= maximumPosition - 1;
    }

    public static void ScrollRichEditToBottom(IntPtr hWnd)
    {
        if (hWnd != IntPtr.Zero)
        {
            SendMessage(hWnd, WM_VSCROLL, new IntPtr(SB_BOTTOM), IntPtr.Zero);
        }
    }

    public static void SetRichEditFirstVisibleLine(IntPtr hWnd, int targetLine)
    {
        if (hWnd == IntPtr.Zero)
        {
            return;
        }

        int currentLine = unchecked((int)SendMessage(
            hWnd,
            EM_GETFIRSTVISIBLELINE,
            IntPtr.Zero,
            IntPtr.Zero
        ).ToInt64());
        int lineDelta = Math.Max(0, targetLine) - currentLine;
        if (lineDelta != 0)
        {
            SendMessage(hWnd, EM_LINESCROLL, IntPtr.Zero, new IntPtr(lineDelta));
        }
    }

    public static int[] GetTextChangeRange(string oldText, string newText)
    {
        oldText = oldText ?? String.Empty;
        newText = newText ?? String.Empty;

        int commonLength = Math.Min(oldText.Length, newText.Length);
        int prefixLength = 0;
        while (prefixLength < commonLength && oldText[prefixLength] == newText[prefixLength])
        {
            prefixLength++;
        }

        if (prefixLength > 0 &&
            ((prefixLength < oldText.Length && Char.IsLowSurrogate(oldText[prefixLength])) ||
             (prefixLength < newText.Length && Char.IsLowSurrogate(newText[prefixLength]))))
        {
            prefixLength--;
        }

        int suffixLength = 0;
        while (suffixLength < oldText.Length - prefixLength &&
               suffixLength < newText.Length - prefixLength &&
               oldText[oldText.Length - 1 - suffixLength] == newText[newText.Length - 1 - suffixLength])
        {
            suffixLength++;
        }

        int oldSuffixStart = oldText.Length - suffixLength;
        int newSuffixStart = newText.Length - suffixLength;
        if (suffixLength > 0 &&
            ((oldSuffixStart < oldText.Length && Char.IsLowSurrogate(oldText[oldSuffixStart])) ||
             (newSuffixStart < newText.Length && Char.IsLowSurrogate(newText[newSuffixStart]))))
        {
            suffixLength--;
        }

        return new int[]
        {
            prefixLength,
            oldText.Length - prefixLength - suffixLength,
            newText.Length - prefixLength - suffixLength
        };
    }

    public const byte VK_LWIN = 0x5B;
    public const byte VK_CONTROL = 0x11;
    public const byte VK_L = 0x4C;
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
    private const uint EM_GETFIRSTVISIBLELINE = 0x00CE;
    private const uint EM_LINESCROLL = 0x00B6;
    private const uint WM_VSCROLL = 0x0115;
    private const int SB_VERT = 1;
    private const int SB_BOTTOM = 7;
    private const uint SIF_RANGE = 0x0001;
    private const uint SIF_PAGE = 0x0002;
    private const uint SIF_POS = 0x0004;
}

public sealed class TranscriptRichTextBox : RichTextBox
{
    public event EventHandler UserScrollChanged;

    protected override void WndProc(ref Message message)
    {
        bool isUserScroll = message.Msg == WM_MOUSEWHEEL ||
            message.Msg == WM_VSCROLL ||
            (message.Msg == WM_KEYDOWN && IsScrollKey(unchecked((int)message.WParam.ToInt64())));

        base.WndProc(ref message);

        if (isUserScroll)
        {
            EventHandler handler = UserScrollChanged;
            if (handler != null)
            {
                handler(this, EventArgs.Empty);
            }
        }
    }

    private static bool IsScrollKey(int virtualKey)
    {
        return virtualKey == VK_UP ||
            virtualKey == VK_DOWN ||
            virtualKey == VK_PAGE_UP ||
            virtualKey == VK_PAGE_DOWN ||
            virtualKey == VK_HOME ||
            virtualKey == VK_END;
    }

    private const int WM_KEYDOWN = 0x0100;
    private const int WM_VSCROLL = 0x0115;
    private const int WM_MOUSEWHEEL = 0x020A;
    private const int VK_PAGE_UP = 0x21;
    private const int VK_PAGE_DOWN = 0x22;
    private const int VK_END = 0x23;
    private const int VK_HOME = 0x24;
    private const int VK_UP = 0x26;
    private const int VK_DOWN = 0x28;
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
                                return new IntPtr(1);
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

function Send-LiveCaptionsShortcut {
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_LWIN, 0, 0, [UIntPtr]::Zero)
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_CONTROL, 0, 0, [UIntPtr]::Zero)
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_L, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_L, 0, [NativeWindowTools]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_CONTROL, 0, [NativeWindowTools]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    [NativeWindowTools]::keybd_event([NativeWindowTools]::VK_LWIN, 0, [NativeWindowTools]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
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
        [string]$Pending
    )

    $text = ""
    if ($null -ne $Captured) {
        $text = $Captured
    }

    if (-not [string]::IsNullOrWhiteSpace($Pending)) {
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
        [double]$MaxDistanceRatio
    )

    $leftComparison = Get-ComparisonText $Left
    $rightComparison = Get-ComparisonText $Right

    if ([string]::IsNullOrEmpty($leftComparison) -or [string]::IsNullOrEmpty($rightComparison)) {
        return $false
    }

    $maxLength = [Math]::Max($leftComparison.Length, $rightComparison.Length)
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

$textDisplay = New-Object TranscriptRichTextBox
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
$followTranscriptTail = $true
$transcriptScrollUpdateDepth = 0
$textDisplayTopAnchorPoint = New-Object System.Drawing.Point(1, 1)

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

function ConvertTo-RichTextBoxInternalText {
    param([string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Convert-TextPositionAfterDisplayChange {
    param(
        [int]$Position,
        [int]$ChangeStart,
        [int]$OldLength,
        [int]$NewLength
    )

    if ($Position -le $ChangeStart) {
        return $Position
    }

    $oldChangeEnd = $ChangeStart + $OldLength
    if ($Position -ge $oldChangeEnd) {
        return $Position + $NewLength - $OldLength
    }

    return $ChangeStart + [Math]::Min($Position - $ChangeStart, $NewLength)
}

function Test-TextDisplayAtBottom {
    return [NativeWindowTools]::IsRichEditAtBottom($textDisplay.Handle)
}

function Update-TranscriptTailFollowState {
    if ($script:transcriptScrollUpdateDepth -gt 0) {
        return
    }

    $script:followTranscriptTail = Test-TextDisplayAtBottom
}

function Set-TextDisplayTailVisible {
    [NativeWindowTools]::ScrollRichEditToBottom($textDisplay.Handle)
}

function Get-TranscriptDisplayTextWithBottomPadding {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $lineBreakCharacters = [char[]]@([char]13, [char]10)
    return $Text.TrimEnd($lineBreakCharacters) + [Environment]::NewLine
}

function Set-TranscriptDisplayText {
    param([string]$Text)

    $displayText = Get-TranscriptDisplayTextWithBottomPadding -Text $Text
    $newInternalText = ConvertTo-RichTextBoxInternalText -Text $displayText
    $oldInternalText = ConvertTo-RichTextBoxInternalText -Text $textDisplay.Text
    $textDisplayHandle = $textDisplay.Handle
    $followTail = $script:followTranscriptTail
    $selectionStart = $textDisplay.SelectionStart
    $selectionEnd = $selectionStart + $textDisplay.SelectionLength
    $firstVisibleCharacter = 0
    if (-not $followTail) {
        $firstVisibleCharacter = $textDisplay.GetCharIndexFromPosition($script:textDisplayTopAnchorPoint)
    }

    $changeRange = [NativeWindowTools]::GetTextChangeRange($oldInternalText, $newInternalText)
    $changeStart = $changeRange[0]
    $oldChangeLength = $changeRange[1]
    $newChangeLength = $changeRange[2]

    $script:transcriptScrollUpdateDepth++
    try {
        if ($oldChangeLength -gt 0 -or $newChangeLength -gt 0) {
            $replacementText = $newInternalText.Substring($changeStart, $newChangeLength)
            $textDisplay.Select($changeStart, $oldChangeLength)
            $textDisplay.SelectedText = $replacementText
            $textDisplay.ClearUndo()
        }

        if ($followTail) {
            Set-TextDisplayTailVisible
        } else {
            $selectionStart = Convert-TextPositionAfterDisplayChange `
                -Position $selectionStart `
                -ChangeStart $changeStart `
                -OldLength $oldChangeLength `
                -NewLength $newChangeLength
            $selectionEnd = Convert-TextPositionAfterDisplayChange `
                -Position $selectionEnd `
                -ChangeStart $changeStart `
                -OldLength $oldChangeLength `
                -NewLength $newChangeLength

            $selectionStart = [Math]::Max(0, [Math]::Min($selectionStart, $textDisplay.TextLength))
            $selectionEnd = [Math]::Max($selectionStart, [Math]::Min($selectionEnd, $textDisplay.TextLength))
            $textDisplay.Select($selectionStart, ($selectionEnd - $selectionStart))

            $firstVisibleCharacter = Convert-TextPositionAfterDisplayChange `
                -Position $firstVisibleCharacter `
                -ChangeStart $changeStart `
                -OldLength $oldChangeLength `
                -NewLength $newChangeLength
            $firstVisibleCharacter = [Math]::Max(0, [Math]::Min($firstVisibleCharacter, $textDisplay.TextLength))
            $firstVisibleLine = $textDisplay.GetLineFromCharIndex($firstVisibleCharacter)
            [NativeWindowTools]::SetRichEditFirstVisibleLine($textDisplayHandle, $firstVisibleLine)
        }
    } finally {
        $script:transcriptScrollUpdateDepth = [Math]::Max(0, ($script:transcriptScrollUpdateDepth - 1))
        if ($followTail) {
            $script:followTranscriptTail = $true
        }
    }
}

$isFullScreen = $false
$windowedBounds = $form.Bounds
$windowedSnapMode = "None"
$snapMode = "None"
$normalBounds = $form.Bounds

function Set-TranscriptWindowBounds {
    param([System.Drawing.Rectangle]$Bounds)

    $followTail = $script:followTranscriptTail
    $selectionStart = $textDisplay.SelectionStart
    $selectionLength = $textDisplay.SelectionLength
    $firstVisibleCharacter = 0
    if (-not $followTail) {
        $firstVisibleCharacter = $textDisplay.GetCharIndexFromPosition($script:textDisplayTopAnchorPoint)
    }

    $script:transcriptScrollUpdateDepth++
    try {
        $effectiveMinimumWidth = [Math]::Min($script:preferredMinimumSize.Width, [Math]::Max(1, $Bounds.Width))
        $effectiveMinimumHeight = [Math]::Min($script:preferredMinimumSize.Height, [Math]::Max(1, $Bounds.Height))
        $form.MinimumSize = New-Object System.Drawing.Size($effectiveMinimumWidth, $effectiveMinimumHeight)
        $form.Bounds = $Bounds
        $form.PerformLayout()

        if ($followTail) {
            Set-TextDisplayTailVisible
        } else {
            $selectionStart = [Math]::Min($selectionStart, $textDisplay.TextLength)
            $selectionLength = [Math]::Min($selectionLength, $textDisplay.TextLength - $selectionStart)
            $textDisplay.Select($selectionStart, $selectionLength)
            $firstVisibleCharacter = [Math]::Max(0, [Math]::Min($firstVisibleCharacter, $textDisplay.TextLength))
            $firstVisibleLine = $textDisplay.GetLineFromCharIndex($firstVisibleCharacter)
            [NativeWindowTools]::SetRichEditFirstVisibleLine($textDisplay.Handle, $firstVisibleLine)
        }
    } finally {
        $script:transcriptScrollUpdateDepth = [Math]::Max(0, ($script:transcriptScrollUpdateDepth - 1))
        if ($followTail) {
            $script:followTranscriptTail = $true
        }
    }
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
        [int]$MinimumWidth,
        [int]$MinimumHeight
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
        [ValidateSet("Left", "Right")]
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
        $isInDirection = if ($Direction -eq "Left") {
            $candidateCenterX -lt $currentCenterX
        } else {
            $candidateCenterX -gt $currentCenterX
        }
        if (-not $isInDirection) {
            continue
        }

        $hasPerpendicularOverlap = $candidateBounds.Top -lt $currentBounds.Bottom -and
            $candidateBounds.Bottom -gt $currentBounds.Top
        $perpendicularGap = 0.0
        if (-not $hasPerpendicularOverlap) {
            $perpendicularGap = [Math]::Min(
                [Math]::Abs($candidateBounds.Top - $currentBounds.Bottom),
                [Math]::Abs($currentBounds.Top - $candidateBounds.Bottom)
            )
        }
        $primaryDistance = [Math]::Abs($candidateCenterX - $currentCenterX)
        $perpendicularCenterDistance = [Math]::Abs($candidateCenterY - $currentCenterY)

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
        [int]$MinimumWidth,
        [int]$MinimumHeight
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
        [System.Windows.Forms.Screen]$Screen,
        [System.Drawing.Rectangle]$RestoreBounds
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
        [bool]$IsPortrait,
        [bool]$CanSplitHorizontally
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
$resizeScrollTrackingActive = $false
$f11Held = $false
$form.Add_FormClosed({ $script:formClosed = $true })
$form.Add_ResizeBegin({
    $script:followTailAfterResize = $script:followTranscriptTail
    if (-not $script:resizeScrollTrackingActive) {
        $script:transcriptScrollUpdateDepth++
        $script:resizeScrollTrackingActive = $true
    }
})
$form.Add_ResizeEnd({
    try {
        if ($script:followTailAfterResize) {
            Set-TextDisplayTailVisible
        }
    } finally {
        if ($script:resizeScrollTrackingActive) {
            $script:transcriptScrollUpdateDepth = [Math]::Max(0, ($script:transcriptScrollUpdateDepth - 1))
            $script:resizeScrollTrackingActive = $false
        }
        if ($script:followTailAfterResize) {
            $script:followTranscriptTail = $true
        }
        $script:followTailAfterResize = $false
    }
})
$textDisplay.Add_UserScrollChanged({ Update-TranscriptTailFollowState })
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
[ForegroundWinArrowMonitor]::Install($form.Handle) | Out-Null

$ownedLiveCaptionsProcessId = 0
$lastLiveCaptionsStartAttempt = [DateTime]::MinValue
Close-LiveCaptions
Send-LiveCaptionsShortcut
$lastLiveCaptionsStartAttempt = Get-Date

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
        return
    }

    $mergedText = Merge-CaptionText -Existing $script:capturedText -Snapshot $Line
    if ($mergedText -ne $script:capturedText) {
        $script:capturedText = $mergedText
    }
}

function Flush-PendingCaptionText {
    if ([string]::IsNullOrWhiteSpace($script:pendingCaptionText)) {
        return
    }

    if (-not (Test-RescuableCaptionLine $script:pendingCaptionText)) {
        $script:pendingCaptionText = ""
        return
    }

    Add-CapturedCaptionLine -Line $script:pendingCaptionText
    $script:pendingCaptionText = ""
}

function Wait-ForNextTranscriptPoll {
    param([int]$Milliseconds)

    $waitTimer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($waitTimer.ElapsedMilliseconds -lt $Milliseconds -and
        -not $script:formClosed -and
        -not $form.IsDisposed) {
        [System.Windows.Forms.Application]::DoEvents()
        if ($script:formClosed -or $form.IsDisposed) {
            break
        }

        Invoke-PendingWinArrowShortcuts | Out-Null

        $remainingMilliseconds = $Milliseconds - $waitTimer.ElapsedMilliseconds
        if ($remainingMilliseconds -gt 0) {
            Start-Sleep -Milliseconds ([Math]::Min(15, [Math]::Max(1, $remainingMilliseconds)))
        }
    }
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

            Wait-ForNextTranscriptPoll -Milliseconds $PollMilliseconds
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
            Wait-ForNextTranscriptPoll -Milliseconds $PollMilliseconds
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
            Wait-ForNextTranscriptPoll -Milliseconds $PollMilliseconds
            continue
        }

        $snapshotLines = @(Split-CaptionLines $snapshot)
        if ($snapshotLines.Count -eq 0) {
            Wait-ForNextTranscriptPoll -Milliseconds $PollMilliseconds
            continue
        }

        for ($lineIndex = 0; $lineIndex -lt ($snapshotLines.Count - 1); $lineIndex++) {
            Add-CapturedCaptionLine -Line $snapshotLines[$lineIndex]
        }

        $pendingCaptionText = Normalize-CaptionText $snapshotLines[$snapshotLines.Count - 1]

        $displayText = Get-TranscriptText -Captured $capturedText -Pending $pendingCaptionText
        if (-not [string]::IsNullOrWhiteSpace($displayText) -and $displayText -ne $lastDisplayedText) {
            Save-CapturedText -Text $displayText
            Set-TranscriptDisplayText -Text $displayText
            $lastDisplayedText = $displayText
        }

        Wait-ForNextTranscriptPoll -Milliseconds $PollMilliseconds
    }
} finally {
    try {
        [ForegroundWinArrowMonitor]::Uninstall()
    } catch {
    }

    try {
        Flush-PendingCaptionText
        $finalText = Get-TranscriptText -Captured $capturedText -Pending $pendingCaptionText
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
