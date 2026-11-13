using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;

namespace Kmao {
    // A document-scoped target. No text is sent to whichever application happens to be active.
    public sealed class OwnedNotepad : IDisposable {
        private IntPtr window, editor;
        private AutomationElement tab;
        private bool disposed, initialized, ownershipLost;
        private string blankTabName, blankWindowTitle;
        private const string Marker = "KMAO BOT is running...";
        private int startupPosition;
        public bool StartupComplete { get { return startupPosition >= Marker.Length; } }
        public bool OwnershipLost { get { return ownershipLost; } }
        public IntPtr Window { get { return window; } }
        public bool IsOpen {
            get {
                if (disposed || window == IntPtr.Zero || !IsWindow(window)) return false;
                if (tab == null) return IsWindow(editor);
                try { return tab.Current.ProcessId > 0; } catch (ElementNotAvailableException) { return false; }
            }
        }
        public bool IsForeground {
            get {
                if (!IsOpen || GetForegroundWindow() != window || !IsOwnedTabSelected()) return false;
                if (initialized && !HasOwnedIdentity()) { ownershipLost = true; return false; }
                return !ownershipLost;
            }
        }
        public int[] EditorBounds {
            get { editor = IsOpen && IsOwnedTabSelected() ? FindEditor(AutomationElement.FromHandle(window)) : IntPtr.Zero; RECT rect; if (editor == IntPtr.Zero || !GetWindowRect(editor, out rect)) throw new InvalidOperationException("Owned Notepad editor is unavailable"); return new int[] { rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top }; }
        }
        public OwnedNotepad() {
            IntPtr[] existing = NotepadWindows();
            HashSet<IntPtr> before = new HashSet<IntPtr>(existing);
            IntPtr initial = IntPtr.Zero;
            foreach (IntPtr candidate in existing) {
                if (!IsIconic(candidate)) { initial = candidate; if (candidate == GetForegroundWindow()) break; }
            }
            // An existing window exposes New Window directly. Starting Notepad again
            // can otherwise add an unrelated blank tab to the user's session.
            if (initial == IntPtr.Zero) {
                string executable = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "notepad.exe");
                using (Process process = Process.Start(new ProcessStartInfo(executable) { UseShellExecute = true, WindowStyle = ProcessWindowStyle.Maximized })) { }
            }
            var timer = Stopwatch.StartNew();
            while (initial == IntPtr.Zero && timer.Elapsed.TotalSeconds < 12) {
                foreach (IntPtr candidate in NotepadWindows()) {
                    if (!before.Contains(candidate)) { initial = candidate; break; }
                    if (candidate == GetForegroundWindow()) initial = candidate;
                }
                if (initial == IntPtr.Zero) Thread.Sleep(100);
            }
            if (initial == IntPtr.Zero) throw new InvalidOperationException("Windows Notepad did not open");
            AutomationElement root = AutomationElement.FromHandle(initial);
            IntPtr candidateEditor = FindEditor(root);
            timer.Restart();
            while (candidateEditor == IntPtr.Zero && timer.Elapsed.TotalSeconds < 5) {
                Thread.Sleep(100); root = AutomationElement.FromHandle(initial); candidateEditor = FindEditor(root);
            }
            if (candidateEditor == IntPtr.Zero) throw new InvalidOperationException("Notepad is not ready; close its startup/settings dialogs and try again");
            var tabs = FindTabs(root);
            // Never claim a restored document or a pre-existing window as our own.
            if (!before.Contains(initial) && tabs.Count <= 1 && candidateEditor != IntPtr.Zero &&
                Message(candidateEditor, 0x000E, IntPtr.Zero, IntPtr.Zero).ToInt64() == 0 &&
                (tabs.Count == 0 && NativeClass(candidateEditor) == "Edit" || tabs.Count == 1 && IsUntitledTab(tabs[0]))) {
                window = initial;
            }
            else {
                var previousWindows = new HashSet<IntPtr>(NotepadWindows());
                InvokeNewWindow(root);
                timer.Restart();
                while (window == IntPtr.Zero && timer.Elapsed.TotalSeconds < 8) {
                    foreach (IntPtr candidate in NotepadWindows()) if (!previousWindows.Contains(candidate)) { window = candidate; break; }
                    if (window == IntPtr.Zero) Thread.Sleep(100);
                }
                if (window == IntPtr.Zero) throw new InvalidOperationException("Notepad could not create an isolated window. No existing document was edited.");
            }
            try {
                root = AutomationElement.FromHandle(window);
                timer.Restart();
                while ((editor = FindEditor(root)) == IntPtr.Zero && timer.Elapsed.TotalSeconds < 5) Thread.Sleep(100);
                tabs = FindTabs(root);
                if (editor == IntPtr.Zero || tabs.Count > 1 || Message(editor, 0x000E, IntPtr.Zero, IntPtr.Zero).ToInt64() != 0)
                    throw new InvalidOperationException("New Notepad window is not an empty isolated document");
                tab = tabs.Count == 1 ? tabs[0] : null;
                blankTabName = tab == null ? null : ReadTabLabel(tab);
                if (tab != null && blankTabName == null) throw new InvalidOperationException("Notepad does not expose its document title for safe ownership tracking");
                blankWindowTitle = ReadWindowTitle(window);
                ShowWindow(window, 3); // SW_MAXIMIZE, only for the window we just created.
                initialized = true;
            }
            catch { Dispose(); throw; }
        }
        public bool IsOwnedTabSelected() {
            if (!IsOpen) return false;
            try {
                if (tab == null) return true; // Classic Notepad has no tabs.
                object pattern;
                return tab.TryGetCurrentPattern(SelectionItemPattern.Pattern, out pattern) && ((SelectionItemPattern)pattern).Current.IsSelected;
            } catch (ElementNotAvailableException) { return false; }
        }
        public void MaximizeAndActivate() {
            if (!IsOpen) throw new InvalidOperationException("Owned Notepad was closed");
            if (tab != null) {
                object pattern;
                if (!tab.TryGetCurrentPattern(SelectionItemPattern.Pattern, out pattern)) throw new InvalidOperationException("Owned Notepad tab is unavailable");
                ((SelectionItemPattern)pattern).Select();
            }
            ShowWindow(window, 3);
            SetForegroundWindow(window); // Only startup, explicit Run, or an idle-resume transition.
        }
        public bool IsEditorPoint(int x, int y) {
            if (!IsForeground) return false;
            POINT point = new POINT(); point.x = x; point.y = y;
            IntPtr hit = WindowFromPoint(point);
            return hit == editor || IsChild(editor, hit);
        }
        public void ClickEditor(int x, int y) {
            if (!IsEditorPoint(x, y)) throw new OperationCanceledException("Owned editor is not available for clicking");
            POINT point = new POINT(); point.x = x; point.y = y;
            RECT client;
            if (!ScreenToClient(editor, ref point) || !GetClientRect(editor, out client) || point.x < 0 || point.y < 0 || point.x >= client.right || point.y >= client.bottom)
                throw new OperationCanceledException("Click is outside the owned editor client area");
            IntPtr position = new IntPtr((point.x & 0xFFFF) | ((point.y & 0xFFFF) << 16));
            // Address the editor itself, never send a global button press to another app.
            try { Message(editor, 0x0201, new IntPtr(1), position); }
            finally { if (IsWindow(editor)) Message(editor, 0x0202, IntPtr.Zero, position); }
        }
        public bool IsCursorOverEditor() {
            POINT point;
            return GetCursorPos(out point) && IsEditorPoint(point.x, point.y);
        }
        public void TypeStartupCharacter() {
            if (StartupComplete) return;
            if (!IsForeground) throw new OperationCanceledException("Owned Notepad is not in the foreground");
            AppendOwnedText(Marker[startupPosition].ToString());
            startupPosition++;
            if (StartupComplete) AppendOwnedText("\r\n");
        }
        public void AppendText(string text) {
            if (!StartupComplete) throw new InvalidOperationException("Type the startup message before appending phrases");
            AppendOwnedText(text);
        }
        private void AppendOwnedText(string text) {
            if (!IsOpen || !IsOwnedTabSelected()) throw new OperationCanceledException("Owned Notepad tab is not selected");
            editor = FindEditor(AutomationElement.FromHandle(window));
            if (editor == IntPtr.Zero) throw new OperationCanceledException("Owned editor is unavailable");
            if (initialized && !HasOwnedIdentity()) { ownershipLost = true; throw new OperationCanceledException("Notepad document was replaced; preserving it"); }
            Message(editor, 0x00B1, new IntPtr(-1), new IntPtr(-1)); // EM_SETSEL: append only to our editor.
            TextMessage(editor, 0x00C2, new IntPtr(1), text); // EM_REPLACESEL, Unicode; no global keyboard input.
        }
        public void Dispose() {
            if (disposed) return;
            try {
                if (IsOpen) {
                    if (tab != null) {
                        object pattern;
                        if (!tab.TryGetCurrentPattern(SelectionItemPattern.Pattern, out pattern)) throw new InvalidOperationException("Owned Notepad tab cannot be selected for cleanup");
                        ((SelectionItemPattern)pattern).Select();
                    }
                    if (!IsOwnedTabSelected()) throw new InvalidOperationException("Owned Notepad tab was not selected; other documents were preserved");
                    var root = AutomationElement.FromHandle(window);
                    editor = FindEditor(root);
                    if (editor == IntPtr.Zero) throw new InvalidOperationException("Owned editor cannot be cleared");
                    if (initialized && !HasOwnedIdentity()) { ownershipLost = true; return; }
                    initialized = false;
                    // Clear only this document; explicit tab close avoids modern session restore.
                    TextMessage(editor, 0x000C, IntPtr.Zero, "");
                    Message(editor, 0x00B9, IntPtr.Zero, IntPtr.Zero);
                    if (tab != null && FindTabs(root).Count > 1) {
                        var close = tab.FindFirst(TreeScope.Descendants, new AndCondition(
                            new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button),
                            new PropertyCondition(AutomationElement.AutomationIdProperty, "CloseButton")));
                        if (close == null) throw new InvalidOperationException("Owned Notepad tab close button is unavailable; other tabs were preserved");
                        InvokeOrExpand(close);
                    }
                    else PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero);
                    var timer = Stopwatch.StartNew();
                    while (OwnTabStillPresent() && timer.Elapsed.TotalSeconds < 3) {
                        DismissOwnSaveDialog(); Thread.Sleep(50);
                    }
                    if (OwnTabStillPresent()) throw new InvalidOperationException("Notepad did not close its bot document automatically; bot text was cleared and other documents were preserved");
                }
            }
            catch (ElementNotAvailableException) { }
            finally { disposed = true; }
        }
        private static string ReadTabLabel(AutomationElement element) {
            var title = element.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Text));
            return title == null ? null : title.Current.Name;
        }
        private static bool IsUntitledTab(AutomationElement element) {
            string label = ReadTabLabel(element);
            // Unknown locales take the isolation path instead of claiming a saved file.
            return label != null && System.Text.RegularExpressions.Regex.IsMatch(label, @"^(Untitled|Sem título)( \d+)?$", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        }
        private static string NormalizeLabel(string value) { return (value ?? "").Trim().Trim('*').Trim(); }
        private bool HasOwnedIdentity() {
            // A manually saved/opened file is no longer a disposable scratch document.
            string rawLabel = tab == null ? ReadWindowTitle(window) : ReadTabLabel(tab);
            if (rawLabel == null) return false;
            string label = NormalizeLabel(rawLabel);
            bool sameLabel = tab == null ? label == NormalizeLabel(blankWindowTitle) : label == NormalizeLabel(blankTabName) || label == Marker || Marker.StartsWith(label, StringComparison.Ordinal);
            return sameLabel && HasOwnedMarker();
        }
        private static string ReadWindowTitle(IntPtr handle) {
            var name = new StringBuilder(1024); GetWindowText(handle, name, name.Capacity); return name.ToString();
        }
        private bool HasOwnedMarker() {
            // Read only the fixed-length ownership prefix, never log document contents.
            string expected = Marker.Substring(0, startupPosition);
            if (!StartupComplete && Message(editor, 0x000E, IntPtr.Zero, IntPtr.Zero).ToInt64() != expected.Length) return false;
            if (expected.Length == 0) return true;
            var prefix = new StringBuilder(expected.Length + 1);
            IntPtr result;
            return ReadTextMessageTimeout(editor, 0x000D, new IntPtr(prefix.Capacity), prefix, 2, 1500, out result) != IntPtr.Zero && prefix.ToString() == expected;
        }
        private bool OwnTabStillPresent() {
            if (!IsWindow(window)) return false;
            if (tab == null) return true;
            try {
                foreach (var current in FindTabs(AutomationElement.FromHandle(window))) if (Automation.Compare(current, tab)) return true;
            } catch (ElementNotAvailableException) { }
            return false;
        }
        private void DismissOwnSaveDialog() {
            if (!IsWindow(window)) return;
            var roots = new List<IntPtr>(); roots.Add(window);
            EnumWindows(delegate(IntPtr h, IntPtr unused) { if (GetWindow(h, 4) == window) roots.Add(h); return true; }, IntPtr.Zero);
            foreach (IntPtr handle in roots) {
                AutomationElement root;
                try { root = AutomationElement.FromHandle(handle); } catch (ElementNotAvailableException) { continue; }
                var buttons = root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button));
                foreach (AutomationElement button in buttons) {
                    string name = button.Current.Name;
                    string id = button.Current.AutomationId;
                    if (id == "7" || id == "DontSaveButton" || name == "Don't save" || name == "Do not save" || name == "N\u00e3o salvar") {
                        object action;
                        if (button.TryGetCurrentPattern(InvokePattern.Pattern, out action)) { ((InvokePattern)action).Invoke(); return; }
                    }
                }
            }
        }
        private static void InvokeNewWindow(AutomationElement root) {
            AutomationElement menu = null;
            var items = root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.MenuItem));
            foreach (AutomationElement item in items) {
                string id = item.Current.AutomationId, name = item.Current.Name;
                if (id == "FileMenuItem" || id == "FileMenuButton" || id == "File" || name == "File" || name == "Arquivo") { menu = item; break; }
            }
            if (menu == null) throw new InvalidOperationException("This Notepad version does not expose its File menu to automation");
            InvokeOrExpand(menu);
            // Query only this Notepad process, never traverse the UI trees of other apps.
            var menuTimer = Stopwatch.StartNew();
            do {
                Thread.Sleep(100);
                var roots = new List<AutomationElement>(); roots.Add(root);
                foreach (AutomationElement popup in AutomationElement.RootElement.FindAll(TreeScope.Children,
                    new PropertyCondition(AutomationElement.ProcessIdProperty, root.Current.ProcessId))) roots.Add(popup);
                foreach (AutomationElement container in roots) {
                    var all = container.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.MenuItem));
                    foreach (AutomationElement item in all) {
                        string id = item.Current.AutomationId, name = item.Current.Name;
                        string accelerator = item.Current.AcceleratorKey.Replace(" ", "").Replace("Control", "Ctrl");
                        bool match = id == "NewWindowMenuFlyoutItem" || accelerator.Equals("Ctrl+Shift+N", StringComparison.OrdinalIgnoreCase) || name == "New window" || name == "Nova janela";
                        if (match) { InvokeOrExpand(item); return; }
                    }
                }
            } while (menuTimer.Elapsed.TotalSeconds < 2);
            throw new InvalidOperationException("Notepad did not expose the new-window command");
        }
        private static void InvokeOrExpand(AutomationElement element) {
            object pattern;
            if (element.TryGetCurrentPattern(InvokePattern.Pattern, out pattern)) ((InvokePattern)pattern).Invoke();
            else if (element.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out pattern)) ((ExpandCollapsePattern)pattern).Expand();
            else throw new InvalidOperationException("Notepad command cannot be invoked");
        }
        private static List<AutomationElement> FindTabs(AutomationElement root) {
            var result = new List<AutomationElement>();
            foreach (AutomationElement element in root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.TabItem))) result.Add(element);
            return result;
        }
        private static IntPtr FindEditor(AutomationElement root) {
            var condition = new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Document), new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit));
            foreach (AutomationElement element in root.FindAll(TreeScope.Descendants, condition)) {
                string cls = element.Current.ClassName;
                if ((cls == "Edit" || cls.StartsWith("RichEdit", StringComparison.OrdinalIgnoreCase)) && element.Current.NativeWindowHandle != 0 && !element.Current.IsOffscreen)
                    return new IntPtr(element.Current.NativeWindowHandle);
            }
            return IntPtr.Zero;
        }
        private static IntPtr[] NotepadWindows() {
            var result = new List<IntPtr>();
            EnumWindows(delegate(IntPtr h, IntPtr unused) {
                if (!IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero) return true;
                uint pid; GetWindowThreadProcessId(h, out pid);
                try { using (Process p = Process.GetProcessById((int)pid)) if (p.ProcessName.Equals("notepad", StringComparison.OrdinalIgnoreCase)) result.Add(h); }
                catch (ArgumentException) { }
                return true;
            }, IntPtr.Zero);
            return result.ToArray();
        }
        private static string NativeClass(IntPtr handle) {
            var name = new StringBuilder(256); GetClassName(handle, name, name.Capacity); return name.ToString();
        }
        private static IntPtr Message(IntPtr handle, uint message, IntPtr w, IntPtr l) {
            IntPtr result;
            if (SendMessageTimeout(handle, message, w, l, 2, 1500, out result) == IntPtr.Zero) throw new InvalidOperationException("Notepad editor did not respond");
            return result;
        }
        private static void TextMessage(IntPtr handle, uint message, IntPtr w, string text) {
            IntPtr result;
            if (SendTextMessageTimeout(handle, message, w, text, 2, 1500, out result) == IntPtr.Zero) throw new InvalidOperationException("Notepad editor did not respond to text");
        }
        private delegate bool EnumProc(IntPtr h, IntPtr l);
        [StructLayout(LayoutKind.Sequential)] private struct POINT { public int x, y; }
        [DllImport("user32.dll")] private static extern bool ScreenToClient(IntPtr window, ref POINT point);
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out RECT rect);
        [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT point);
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(POINT point);
        [DllImport("user32.dll")] private static extern bool IsChild(IntPtr parent, IntPtr child);
        [StructLayout(LayoutKind.Sequential)] private struct RECT { public int left, top, right, bottom; }
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr h,StringBuilder name,int count);
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr h,StringBuilder name,int count);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr l);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr h, uint command);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out RECT rect);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int command);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern IntPtr SendMessageTimeout(IntPtr h,uint message,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
        [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW",CharSet=CharSet.Unicode)] private static extern IntPtr ReadTextMessageTimeout(IntPtr h,uint message,IntPtr w,StringBuilder text,uint flags,uint timeout,out IntPtr result);
        [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW",CharSet=CharSet.Unicode)] private static extern IntPtr SendTextMessageTimeout(IntPtr h,uint message,IntPtr w,string text,uint flags,uint timeout,out IntPtr result);
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr h,uint message,IntPtr w,IntPtr l);
    }
}
