using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace Kmao {
    // UI callbacks remain in C#: PowerShell scriptblocks must not run on this STA thread.
    public sealed class TrayController : IDisposable {
        private readonly Thread thread;
        private readonly ManualResetEvent ready = new ManualResetEvent(false);
        private readonly ConcurrentQueue<string> notices = new ConcurrentQueue<string>();
        private readonly string logFile, logViewer, version;
        private ApplicationContext context;
        private Control dispatcher;
        private NotifyIcon tray;
        private ToolStripMenuItem runItem, stopItem;
        private Icon runningIcon, stoppedIcon;
        private Exception failure;
        private volatile bool enabled = true, exitRequested, disposed;
        public bool Enabled { get { return enabled; } }
        public bool ExitRequested { get { return exitRequested; } }
        public string[] DrainNotices() { var result = new System.Collections.Generic.List<string>(); string line; while (notices.TryDequeue(out line)) result.Add(line); return result.ToArray(); }

        public TrayController(string logFile, string logViewer, string version) {
            this.logFile = logFile; this.logViewer = logViewer; this.version = version;
            thread = new Thread(Run); thread.IsBackground = true;
            thread.SetApartmentState(ApartmentState.STA); thread.Name = "KMAO tray";
            thread.Start();
            if (!ready.WaitOne(10000)) { exitRequested = true; throw new TimeoutException("Tray did not start"); }
            CheckHealth();
        }
        public void CheckHealth() {
            if (failure != null) throw new InvalidOperationException("Tray failed", failure);
            if (!disposed && !thread.IsAlive) throw new InvalidOperationException("Tray thread stopped unexpectedly");
        }
        public void SetEnabled(bool value) {
            enabled = value;
            if (dispatcher != null && !dispatcher.IsDisposed)
                dispatcher.BeginInvoke((Action)delegate { RefreshState(); });
        }
        public void RequestExit() { exitRequested = true; enabled = false; }
        private void RefreshState() {
            runItem.Visible = !enabled; stopItem.Visible = enabled;
            tray.Icon = enabled ? runningIcon : stoppedIcon;
            tray.Text = "KMAO " + version + (enabled ? " - Running" : " - Stopped");
        }
        private void Run() {
            try {
                dispatcher = new Control(); IntPtr handle = dispatcher.Handle;
                context = new ApplicationContext();
                runningIcon = CreateRobotIcon(Color.FromArgb(36, 167, 82));
                stoppedIcon = CreateRobotIcon(Color.FromArgb(135, 140, 148));
                var menu = new ContextMenuStrip();
                runItem = new ToolStripMenuItem("Run", null, delegate { enabled = true; RefreshState(); notices.Enqueue("Run selected."); });
                stopItem = new ToolStripMenuItem("Stop", null, delegate { enabled = false; RefreshState(); notices.Enqueue("Stop selected; automatic cycle cancelled."); });
                menu.Items.Add(runItem); menu.Items.Add(stopItem); menu.Items.Add(new ToolStripSeparator());
                menu.Items.Add("Logs", null, delegate { try { OpenLogs(logFile, logViewer); } catch (Exception ex) { notices.Enqueue("Logs failed: " + ex.Message); } });
                menu.Items.Add("About", null, delegate { try { Process.Start(new ProcessStartInfo("https://github.com/gut0leao/kmao-bot") { UseShellExecute = true }); } catch (Exception ex) { notices.Enqueue("About failed: " + ex.Message); } });
                menu.Items.Add(new ToolStripSeparator());
                menu.Items.Add("Exit", null, delegate { RequestExit(); notices.Enqueue("Exit selected."); });
                tray = new NotifyIcon(); tray.ContextMenuStrip = menu;
                tray.DoubleClick += delegate { enabled = !enabled; RefreshState(); notices.Enqueue(enabled ? "Run selected." : "Stop selected."); };
                RefreshState(); tray.Visible = true; ready.Set();
                Application.Run(context);
            } catch (Exception ex) { failure = ex; exitRequested = true; }
            finally {
                if (tray != null) { tray.Visible = false; if (tray.ContextMenuStrip != null) tray.ContextMenuStrip.Dispose(); tray.Dispose(); }
                if (runningIcon != null) runningIcon.Dispose();
                if (stoppedIcon != null) stoppedIcon.Dispose();
                if (dispatcher != null) dispatcher.Dispose();
                if (context != null) context.Dispose();
                ready.Set();
            }
        }
        public static void OpenLogs(string file, string viewer) {
            if (!File.Exists(file) || !File.Exists(viewer)) throw new FileNotFoundException("Log or log viewer is missing");
            string executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe");
            Process.Start(new ProcessStartInfo(executable, "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + viewer + "\" -LogPath \"" + file + "\"") { UseShellExecute = true });
        }
        public static Icon CreateRobotIcon(Color color) {
            using (var bitmap = new Bitmap(32, 32)) {
                using (Graphics g = Graphics.FromImage(bitmap)) {
                    g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(Color.Transparent);
                    using (var brush = new SolidBrush(color))
                    using (var border = new Pen(Color.FromArgb(45, 50, 58), 2))
                    using (var light = new Pen(Color.White, 2)) {
                        g.DrawLine(border, 16, 4, 16, 8); g.FillEllipse(brush, 13, 1, 6, 6);
                        g.FillRectangle(brush, 5, 8, 22, 21); g.DrawRectangle(border, 5, 8, 22, 21);
                        g.FillRectangle(brush, 1, 14, 4, 9); g.FillRectangle(brush, 27, 14, 4, 9);
                        g.FillEllipse(Brushes.White, 9, 13, 5, 5); g.FillEllipse(Brushes.White, 19, 13, 5, 5);
                        g.DrawArc(light, 11, 18, 10, 6, 0, 180);
                    }
                }
                IntPtr icon = bitmap.GetHicon();
                try { return (Icon)Icon.FromHandle(icon).Clone(); } finally { DestroyIcon(icon); }
            }
        }
        public static bool HideOwnedConsole() {
            string[] arguments = Environment.GetCommandLineArgs();
            bool standalone = false;
            for (int i = 0; i < arguments.Length; i++) {
                if (arguments[i].Equals("-NoExit", StringComparison.OrdinalIgnoreCase)) return false;
                if (arguments[i].Equals("-File", StringComparison.OrdinalIgnoreCase) && i + 1 < arguments.Length) {
                    string script = Path.GetFileName(arguments[i + 1]);
                    standalone = script.Equals("Start-Kmao.ps1", StringComparison.OrdinalIgnoreCase) || script.Equals("Launch-Kmao.ps1", StringComparison.OrdinalIgnoreCase) || script.Equals("dev.ps1", StringComparison.OrdinalIgnoreCase);
                }
            }
            if (!standalone) return false;
            uint[] ids = new uint[2];
            if (GetConsoleProcessList(ids, 2) != 1 || ids[0] != Process.GetCurrentProcess().Id) return false;
            IntPtr window = GetConsoleWindow();
            if (window == IntPtr.Zero) return false;
            ShowWindow(window, 0); return true;
        }
        public static void ShowConsole() { IntPtr window = GetConsoleWindow(); if (window != IntPtr.Zero) ShowWindow(window, 5); }
        public void Dispose() {
            if (disposed) return;
            exitRequested = true; enabled = false;
            if (dispatcher != null && !dispatcher.IsDisposed)
                dispatcher.BeginInvoke((Action)delegate { context.ExitThread(); });
            if (!thread.Join(5000)) throw new TimeoutException("Tray did not stop");
            disposed = true; ready.Dispose();
        }
        [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);
        [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")] private static extern uint GetConsoleProcessList(uint[] ids, uint count);
    }
}
