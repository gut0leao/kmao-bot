using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("KMAO Bot")]
[assembly: AssemblyDescription("KMAO Bot")]
[assembly: AssemblyProduct("KMAO Bot")]
[assembly: AssemblyCompany("gut0leao")]

namespace Kmao {
    // The tray and PowerShell engine live in THIS process, never a renamed or
    // copied powershell.exe. Only the adjacent application entry point is run.
    internal static class BotProgram {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
        [STAThread]
        private static int Main(string[] args) {
            string health = null;
            string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            try {
                for (int i = 0; i < args.Length; i++) {
                    if (args[i] == "--version" && args.Length == 1) {
                        Console.WriteLine(Assembly.GetExecutingAssembly().GetName().Version.ToString(3)); return 0;
                    }
                    if (args[i].Equals("-HealthToken", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) {
                        Guid value;
                        health = args[++i];
                        if (!Guid.TryParseExact(health, "N", out value)) throw new ArgumentException("Invalid health token");
                    }
                    else if (args[i].Equals("-ProfileDirectory", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) {
                        profile = Path.GetFullPath(args[++i]);
                    }
                    else throw new ArgumentException("Unsupported KMAO Bot argument: " + args[i]);
                }
                int identity = SetCurrentProcessExplicitAppUserModelID("Kmao.Bot");
                if (identity < 0) Marshal.ThrowExceptionForHR(identity);
                Application.EnableVisualStyles();
                string entry = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "dev.ps1");
                if (!File.Exists(entry)) throw new FileNotFoundException("Incomplete KMAO installation: dev.ps1 is missing", entry);
                var host = new BotHost();
                var state = InitialSessionState.CreateDefault();
                // Same process-scoped policy as the existing shortcuts; does not
                // override Windows App Control, machine policy, or antivirus.
                state.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
                using (Runspace runspace = RunspaceFactory.CreateRunspace(host, state)) {
                    runspace.ApartmentState = ApartmentState.STA;
                    runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                    runspace.Open();
                    runspace.SessionStateProxy.SetVariable("LASTEXITCODE", 0);
                    using (PowerShell shell = PowerShell.Create()) {
                        shell.Runspace = runspace;
                        shell.AddCommand(entry).AddParameter("ProfileDirectory", profile);
                        if (health != null) shell.AddParameter("HealthToken", health);
                        shell.Invoke();
                        if (host.ExitRequested) return host.ExitCode;
                        if (shell.Streams.Error.Count > 0) throw new InvalidOperationException("Bot failed: " + String.Join(Environment.NewLine, shell.Streams.Error));
                        // A script invoked as a command records `exit N` in
                        // LASTEXITCODE rather than calling the enclosing host.
                        return Convert.ToInt32(runspace.SessionStateProxy.GetVariable("LASTEXITCODE"), CultureInfo.InvariantCulture);
                    }
                }
            }
            catch (Exception error) {
                string message = error.ToString();
                try {
                    string logs = Path.Combine(profile, ".kmao-bot", "logs");
                    Directory.CreateDirectory(logs);
                    string file = Path.Combine(logs, "host-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + "-" + System.Diagnostics.Process.GetCurrentProcess().Id + ".log");
                    File.WriteAllText(file, DateTimeOffset.Now.ToString("o") + " [ERROR] " + message);
                } catch { }
                Console.Error.WriteLine(message);
                if (health == null) MessageBox.Show("KMAO Bot could not start. See the host log in the application logs folder.\n\n" + error.Message, "KMAO Bot", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }
    internal sealed class BotHost : PSHost {
        private readonly Guid id = Guid.NewGuid();
        private readonly BotHostUI ui = new BotHostUI();
        internal bool ExitRequested;
        internal int ExitCode;
        public override Guid InstanceId { get { return id; } }
        public override string Name { get { return "KMAO Bot"; } }
        public override Version Version { get { return Assembly.GetExecutingAssembly().GetName().Version; } }
        public override PSHostUserInterface UI { get { return ui; } }
        public override CultureInfo CurrentCulture { get { return CultureInfo.CurrentCulture; } }
        public override CultureInfo CurrentUICulture { get { return CultureInfo.CurrentUICulture; } }
        public override void SetShouldExit(int exitCode) { ExitCode = exitCode; ExitRequested = true; }
        public override void EnterNestedPrompt() { throw new NotSupportedException("Nested prompts are not supported"); }
        public override void ExitNestedPrompt() { throw new NotSupportedException("Nested prompts are not supported"); }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
    }
    internal sealed class BotHostUI : PSHostUserInterface {
        public override PSHostRawUserInterface RawUI { get { return null; } }
        public override void Write(string value) { Console.Write(value); }
        public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value) { Write(value); }
        public override void WriteLine(string value) { Console.WriteLine(value); }
        public override void WriteErrorLine(string value) { Console.Error.WriteLine(value); }
        public override void WriteDebugLine(string value) { Console.WriteLine(value); }
        public override void WriteVerboseLine(string value) { Console.WriteLine(value); }
        public override void WriteWarningLine(string value) { Console.WriteLine(value); }
        public override void WriteProgress(long sourceId, ProgressRecord record) { }
        public override string ReadLine() { throw new NotSupportedException("Use the KMAO tray menu"); }
        public override System.Security.SecureString ReadLineAsSecureString() { throw new NotSupportedException("Interactive credentials are not supported"); }
        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions) { throw new NotSupportedException("Interactive prompts are not supported"); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName) { throw new NotSupportedException("Interactive credentials are not supported"); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes types, PSCredentialUIOptions options) { throw new NotSupportedException("Interactive credentials are not supported"); }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) { throw new NotSupportedException("Interactive prompts are not supported"); }
    }
}
