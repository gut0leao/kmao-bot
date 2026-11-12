using System;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace Kmao {
    // Hooks run on their own message-pumping thread, never inside a PowerShell callback.
    public sealed class WindowsInput : IDisposable {
        private static readonly UIntPtr OwnInput = new UIntPtr(0x4B4D414F);
        private readonly bool record;
        private readonly int samplingMs;
        private readonly ConcurrentQueue<string> events = new ConcurrentQueue<string>();
        private readonly ManualResetEvent ready = new ManualResetEvent(false);
        private readonly HookProc mouseProc, keyboardProc;
        private readonly Thread thread;
        private IntPtr mouseHook, keyboardHook;
        private uint threadId;
        private Exception failure;
        private long generation, lastActivity, lastSample = -1;
        private int queued, lastX = int.MinValue, lastY = int.MinValue;
        private bool disposed;
        private volatile bool stopping;
        private const int QueueLimit = 100000;
        public long Generation { get { CheckHealth(); return Interlocked.Read(ref generation); } }
        public double IdleSeconds {
            get { CheckHealth(); return (Stopwatch.GetTimestamp() - Interlocked.Read(ref lastActivity)) / (double)Stopwatch.Frequency; }
        }
        public static IntPtr ForegroundWindow { get { return GetForegroundWindow(); } }

        public WindowsInput(bool recordEvents, int mouseSamplingMs) {
            record = recordEvents;
            samplingMs = mouseSamplingMs;
            LASTINPUTINFO info = new LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            if (!GetLastInputInfo(ref info)) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetLastInputInfo failed");
            uint idleMs = unchecked(GetTickCount() - info.dwTime);
            lastActivity = Stopwatch.GetTimestamp() - (long)(idleMs / 1000.0 * Stopwatch.Frequency);
            mouseProc = MouseCallback;
            keyboardProc = KeyboardCallback;
            thread = new Thread(Run);
            thread.IsBackground = true;
            thread.Name = "KMAO input hooks";
            thread.Start();
            if (!ready.WaitOne(5000)) {
                Dispose();
                throw new TimeoutException("Input hooks did not start within 5 seconds");
            }
            try { CheckHealth(); } catch { Dispose(); throw; }
        }

        private void Run() {
            try {
                threadId = GetCurrentThreadId();
                MSG msg;
                PeekMessage(out msg, IntPtr.Zero, 0, 0, 0); // Create the thread message queue.
                if (stopping) return;
                IntPtr module = GetModuleHandle(null);
                mouseHook = SetWindowsHookEx(14, mouseProc, module, 0);
                if (mouseHook == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Mouse hook installation failed");
                keyboardHook = SetWindowsHookEx(13, keyboardProc, module, 0);
                if (keyboardHook == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Keyboard hook installation failed");
                ready.Set();
                if (stopping) return;
                int result;
                while ((result = GetMessage(out msg, IntPtr.Zero, 0, 0)) > 0) {
                    TranslateMessage(ref msg);
                    DispatchMessage(ref msg);
                }
                if (result < 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetMessage failed");
            } catch (Exception ex) { SetFailure(ex); }
            finally {
                // Attempt BOTH removals, including when installation was only partially successful.
                if (keyboardHook != IntPtr.Zero && !UnhookWindowsHookEx(keyboardHook))
                    SetFailure(new Win32Exception(Marshal.GetLastWin32Error(), "Keyboard unhook failed"));
                if (mouseHook != IntPtr.Zero && !UnhookWindowsHookEx(mouseHook))
                    SetFailure(new Win32Exception(Marshal.GetLastWin32Error(), "Mouse unhook failed"));
                ready.Set();
            }
        }

        private void SetFailure(Exception ex) { Interlocked.CompareExchange(ref failure, ex, null); }
        public void CheckHealth() {
            Exception ex = Interlocked.CompareExchange(ref failure, null, null);
            if (ex != null) throw new InvalidOperationException("Input monitoring failed", ex);
            if (disposed) throw new ObjectDisposedException("WindowsInput");
            if (!thread.IsAlive) throw new InvalidOperationException("Input monitoring thread stopped unexpectedly");
        }
        private void Observe(UIntPtr marker) {
            // Only our marked injected events are excluded. Other automation/accessibility input cancels too.
            if (marker == OwnInput) return;
            Interlocked.Exchange(ref lastActivity, Stopwatch.GetTimestamp());
            Interlocked.Increment(ref generation);
        }
        private void Enqueue(string kind, string x, string y, string key) {
            if (!record) return;
            if (Interlocked.Increment(ref queued) > QueueLimit) {
                Interlocked.Decrement(ref queued);
                SetFailure(new InvalidOperationException("Recording queue overflow; recording stopped to avoid silent data loss"));
                return;
            }
            events.Enqueue(DateTimeOffset.UtcNow.ToUnixTimeSeconds() + "," + kind + "," + x + "," + y + "," + key);
        }
        private IntPtr MouseCallback(int code, IntPtr message, IntPtr data) {
            try {
                if (code >= 0) {
                    MOUSEHOOK item = (MOUSEHOOK)Marshal.PtrToStructure(data, typeof(MOUSEHOOK));
                    Observe(item.extra);
                    int msg = message.ToInt32();
                    string kind = null;
                    if (msg == 0x201 || msg == 0x204 || msg == 0x207 || msg == 0x20B) kind = "mc";
                    else if (msg == 0x20A || msg == 0x20E) kind = "sc";
                    else if (msg == 0x200 && record) {
                        long now = Stopwatch.GetTimestamp();
                        if ((item.pt.x != lastX || item.pt.y != lastY) &&
                            (lastSample < 0 || (now - lastSample) * 1000.0 / Stopwatch.Frequency >= samplingMs)) {
                            kind = "mm"; lastX = item.pt.x; lastY = item.pt.y; lastSample = now;
                        }
                    }
                    if (kind != null) Enqueue(kind, item.pt.x.ToString(System.Globalization.CultureInfo.InvariantCulture),
                        item.pt.y.ToString(System.Globalization.CultureInfo.InvariantCulture), "");
                }
            } catch (Exception ex) { SetFailure(ex); }
            return CallNextHookEx(IntPtr.Zero, code, message, data);
        }
        private IntPtr KeyboardCallback(int code, IntPtr message, IntPtr data) {
            try {
                if (code >= 0) {
                    KEYHOOK item = (KEYHOOK)Marshal.PtrToStructure(data, typeof(KEYHOOK));
                    Observe(item.extra);
                    int msg = message.ToInt32();
                    if (msg == 0x100 || msg == 0x104) Enqueue("kd", "", "", item.vk.ToString());
                    else if (msg == 0x101 || msg == 0x105) Enqueue("ku", "", "", item.vk.ToString());
                }
            } catch (Exception ex) { SetFailure(ex); }
            return CallNextHookEx(IntPtr.Zero, code, message, data);
        }
        // Drain in bounded batches so continuous input cannot starve duration/Ctrl+C checks.
        public string[] Drain() {
            var batch = new System.Collections.Generic.List<string>();
            string line;
            while (batch.Count < 1000 && events.TryDequeue(out line)) {
                Interlocked.Decrement(ref queued);
                batch.Add(line);
            }
            return batch.ToArray();
        }
        public bool IsCurrent(long expected, IntPtr window) {
            CheckHealth();
            return Interlocked.Read(ref generation) == expected && (window == IntPtr.Zero || window == GetForegroundWindow());
        }
        private bool Send(long expected, IntPtr window, INPUT[] inputs) {
            if (!IsCurrent(expected, window)) return false;
            uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
            if (sent != inputs.Length) {
                int error = Marshal.GetLastWin32Error();
                // Release paired inputs even if Windows accepted only part of the batch.
                INPUT release = inputs[inputs.Length - 1];
                if (inputs.Length > 1) SendInput(1, new INPUT[] { release }, Marshal.SizeOf(typeof(INPUT)));
                throw new Win32Exception(error, "SendInput failed or was partially accepted (possibly blocked by window permissions)");
            }
            return true;
        }
        private static INPUT Mouse(uint flags, int x, int y) {
            INPUT input = new INPUT(); input.type = 0;
            input.data.mouse.dx = x; input.data.mouse.dy = y;
            input.data.mouse.flags = flags; input.data.mouse.extra = OwnInput;
            return input;
        }
        public bool Move(long expected, int x, int y) {
            int left = GetSystemMetrics(76), top = GetSystemMetrics(77);
            int width = GetSystemMetrics(78), height = GetSystemMetrics(79);
            if (width <= 1 || height <= 1) throw new InvalidOperationException("Invalid virtual screen dimensions");
            int dx = (int)((x - left) * 65535L / (width - 1));
            int dy = (int)((y - top) * 65535L / (height - 1));
            return Send(expected, IntPtr.Zero, new INPUT[] { Mouse(0xC001, dx, dy) });
        }
        public bool Click(long expected, IntPtr window) {
            // Atomic down/up pair: cancellation cannot leave the mouse button held down.
            return Send(expected, window, new INPUT[] { Mouse(2, 0, 0), Mouse(4, 0, 0) });
        }
        public bool TypeCharacter(long expected, IntPtr window, char character) {
            INPUT down = new INPUT(); down.type = 1;
            down.data.keyboard.scan = character; down.data.keyboard.flags = 4;
            down.data.keyboard.extra = OwnInput;
            INPUT up = down; up.data.keyboard.flags |= 2;
            return Send(expected, window, new INPUT[] { down, up });
        }
        public bool Enter(long expected, IntPtr window) {
            INPUT down = new INPUT(); down.type = 1;
            down.data.keyboard.vk = 13; down.data.keyboard.extra = OwnInput;
            INPUT up = down; up.data.keyboard.flags = 2;
            return Send(expected, window, new INPUT[] { down, up });
        }
        public void Dispose() {
            if (disposed) return;
            stopping = true;
            // Startup timeout can happen before the queue exists; wait for the finally/start signal first.
            if (!ready.WaitOne(5000)) throw new TimeoutException("Input thread startup did not finish; cannot stop safely");
            if (thread.IsAlive) {
                if (!PostThreadMessage(threadId, 0x12, UIntPtr.Zero, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not stop input thread");
                if (!thread.Join(5000)) throw new TimeoutException("Input thread did not stop within 5 seconds");
            }
            disposed = true;
            ready.Dispose();
            Exception ex = Interlocked.CompareExchange(ref failure, null, null);
            if (ex != null) throw new InvalidOperationException("Input monitoring or cleanup failed", ex);
        }

        private delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
        [StructLayout(LayoutKind.Sequential)] private struct POINT { public int x, y; }
        [StructLayout(LayoutKind.Sequential)] private struct MOUSEHOOK { public POINT pt; public uint mouseData, flags, time; public UIntPtr extra; }
        [StructLayout(LayoutKind.Sequential)] private struct KEYHOOK { public uint vk, scan, flags, time; public UIntPtr extra; }
        [StructLayout(LayoutKind.Sequential)] private struct LASTINPUTINFO { public uint cbSize, dwTime; }
        [StructLayout(LayoutKind.Sequential)] private struct MSG { public IntPtr hwnd; public uint message; public UIntPtr wParam; public IntPtr lParam; public uint time; public POINT pt; public uint lPrivate; }
        [StructLayout(LayoutKind.Sequential)] private struct MOUSEINPUT { public int dx, dy; public uint mouseData, flags, time; public UIntPtr extra; }
        [StructLayout(LayoutKind.Sequential)] private struct KEYINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
        [StructLayout(LayoutKind.Explicit)] private struct INPUTDATA {
            [FieldOffset(0)] public MOUSEINPUT mouse;
            [FieldOffset(0)] public KEYINPUT keyboard;
        }
        [StructLayout(LayoutKind.Sequential)] private struct INPUT { public uint type; public INPUTDATA data; }
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr module, uint thread);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern IntPtr GetModuleHandle(string module);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
        [DllImport("kernel32.dll")] private static extern uint GetTickCount();
        [DllImport("user32.dll", SetLastError = true)] private static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetMessage(out MSG message, IntPtr window, uint min, uint max);
        [DllImport("user32.dll")] private static extern bool PeekMessage(out MSG message, IntPtr window, uint min, uint max, uint remove);
        [DllImport("user32.dll")] private static extern bool TranslateMessage(ref MSG message);
        [DllImport("user32.dll")] private static extern IntPtr DispatchMessage(ref MSG message);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool PostThreadMessage(uint thread, uint message, UIntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
        [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, INPUT[] inputs, int size);
    }
}
