using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

namespace KevinSetup {
    internal static class Program {
        [STAThread] private static void Main(string[] args) {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            try {
                byte[] bytes;
                using (var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Kevin.Payload.zip")) {
                    if (resource == null) throw new InvalidDataException("Setup has no embedded release.");
                    using (var memory = new MemoryStream()) { resource.CopyTo(memory); bytes = memory.ToArray(); }
                }
                var payload = BundlePayload.Validate(bytes, BuildInfo.ZipSha256);
                var form = new SetupForm(payload);
                if (args.Length != 0) {
                    if (args.Length != 4 || args[0] != "--game-path" || args[2] != "--action" ||
                        (args[3] != "install" && args[3] != "disable"))
                        throw new ArgumentException("Unknown setup arguments. Open Kevin Setup normally.");
                    form.ResumeElevated(args[1], args[3] == "disable");
                }
                Application.Run(form);
            } catch (Exception e) { MessageBox.Show(e.Message, "Kevin setup could not start", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
    }
    internal sealed class SetupForm : Form {
        private readonly BundlePayload payload;
        private readonly TextBox game = new TextBox(), output = new TextBox();
        private readonly Button install = new Button(), disable = new Button(), browse = new Button(), guide = new Button();
        private readonly Button administrator = new Button(), saveReport = new Button();
        private readonly Label status = new Label();
        private bool busy;
        private string extracted;
        private string logPath;
        private string reportText;
        private string lastGame;
        private bool lastDisabling;
        public SetupForm(BundlePayload release) {
            payload = release; Text = "Kevin Companion Setup";
            ClientSize = new Size(650, 504); MinimumSize = new Size(666, 543);
            StartPosition = FormStartPosition.CenterScreen; Font = new Font("Segoe UI", 10);
            var heading = new Label { Text = "Kevin Companion " + payload.Version, Font = new Font(Font, FontStyle.Bold), Left = 22, Top = 20, Width = 600, Height = 28 };
            var detail = new Label { Text = "Single-player preview for Subsistence Alpha 68.19. Close the game first.", Left = 22, Top = 52, Width = 605, Height = 26 };
            var location = new Label { Text = "Subsistence folder", Left = 22, Top = 89, Width = 200, Height = 24 };
            game.SetBounds(22, 117, 494, 28); browse.SetBounds(528, 115, 100, 31); browse.Text = "Browse...";
            install.SetBounds(22, 164, 180, 39); install.Text = "Install / Update";
            disable.SetBounds(214, 164, 180, 39); disable.Text = "Disable Kevin";
            guide.SetBounds(406, 164, 222, 39); guide.Text = "Read player guide";
            status.SetBounds(22, 216, 606, 58); status.Text = "Choose Install, then select Kevin Companion in your profile's Mods list.";
            output.SetBounds(22, 281, 606, 147); output.Multiline = true; output.ReadOnly = true; output.ScrollBars = ScrollBars.Vertical;
            output.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right | AnchorStyles.Bottom;
            administrator.SetBounds(22, 446, 294, 36); administrator.Text = "Retry as administrator"; administrator.Enabled = false;
            saveReport.SetBounds(328, 446, 300, 36); saveReport.Text = "Save setup report..."; saveReport.Enabled = false;
            administrator.Anchor = saveReport.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
            Controls.AddRange(new Control[] { heading, detail, location, game, browse, install, disable, guide, status, output, administrator, saveReport });
            browse.Click += delegate { using (var picker = new FolderBrowserDialog()) { picker.Description = "Choose the Subsistence game folder (contains Binaries and UDKGame)"; picker.SelectedPath = game.Text; if (picker.ShowDialog(this) == DialogResult.OK) game.Text = picker.SelectedPath; } };
            install.Click += delegate { RunInstaller(false); }; disable.Click += delegate { RunInstaller(true); };
            guide.Click += delegate {
                using (var reader = new Form { Text = "Kevin player guide", Size = new Size(740, 620), StartPosition = FormStartPosition.CenterParent }) {
                    reader.Controls.Add(new TextBox { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
                        Font = new Font("Segoe UI", 10), Text = Encoding.UTF8.GetString(payload.Files[payload.Files.ContainsKey("PLAYER-GUIDE.txt") ? "PLAYER-GUIDE.txt" : "README.txt"]).Replace("\n", "\r\n").Replace("\r\r\n", "\r\n") });
                    reader.ShowDialog(this);
                }
            };
            administrator.Click += delegate { RestartElevated(); };
            saveReport.Click += delegate {
                using (var picker = new SaveFileDialog { Filter = "Text report (*.txt)|*.txt", FileName = "Kevin-Setup-report.txt" }) {
                    if (picker.ShowDialog(this) != DialogResult.OK) return;
                    try { File.WriteAllText(picker.FileName, reportText, new UTF8Encoding(false)); }
                    catch (Exception e) { MessageBox.Show(this, e.Message, "Could not save the report"); }
                }
            };
            FormClosing += delegate(object sender, FormClosingEventArgs e) { if (busy) { e.Cancel = true; status.Text = "Please wait for the current file operation to finish."; } };
            var found = FindSteamGames();
            if (found.Count == 1) game.Text = found[0];
            else status.Text = "Choose your Subsistence folder with Browse, then Install or Disable.";
        }
        private static List<string> FindSteamGames() {
            var roots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try { using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")) {
                if (key != null && key.GetValue("SteamPath") is string) roots.Add((string)key.GetValue("SteamPath"));
            } } catch { }
            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            if (programFiles.Length > 0) roots.Add(Path.Combine(programFiles, "Steam"));
            foreach (var root in new List<string>(roots)) {
                try { string file = Path.Combine(root, @"steamapps\libraryfolders.vdf");
                    if (File.Exists(file)) foreach (Match m in Regex.Matches(File.ReadAllText(file), "\"path\"\\s*\"([^\"]+)\"")) roots.Add(m.Groups[1].Value.Replace(@"\\", @"\"));
                } catch { }
            }
            var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var root in roots) {
                try { string file = Path.Combine(root, @"steamapps\appmanifest_418030.acf");
                    if (!File.Exists(file)) continue;
                    Match match = Regex.Match(File.ReadAllText(file), "\"installdir\"\\s*\"([^\"]+)\"");
                    if (!match.Success || match.Groups[1].Value.IndexOfAny(new char[] {'/', '\\', ':'}) >= 0) continue;
                    string path = Path.GetFullPath(Path.Combine(root, @"steamapps\common", match.Groups[1].Value));
                    if (Directory.Exists(Path.Combine(path, @"UDKGame\CookedPC")) && File.Exists(Path.Combine(path, @"Binaries\Win64\Subsistence.exe"))) found.Add(path);
                } catch { }
            }
            return new List<string>(found);
        }
        private void RunInstaller(bool disabling) {
            string selected;
            try {
                selected = Path.GetFullPath(game.Text.Trim()).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                if (!Directory.Exists(Path.Combine(selected, @"UDKGame\CookedPC")) || !File.Exists(Path.Combine(selected, @"Binaries\Win64\Subsistence.exe")))
                    throw new IOException("Choose the Subsistence game folder containing Binaries and UDKGame.");
            } catch (Exception e) { MessageBox.Show(this, e.Message, "Choose the game folder"); return; }
            lastGame = selected; lastDisabling = disabling;
            reportText = "Kevin Setup report\r\nVersion: " + payload.Version + "\r\nBuild: " + payload.BuildId +
                "\r\nAction: " + (disabling ? "Disable" : "Install / Update") + "\r\nGame folder: " + selected +
                "\r\nWindows: " + Environment.OSVersion + "\r\nAdministrator: " + IsAdministrator() + "\r\nUTC: " + DateTime.UtcNow.ToString("o") + "\r\n\r\n";
            busy = true; install.Enabled = disable.Enabled = browse.Enabled = guide.Enabled = game.Enabled = administrator.Enabled = saveReport.Enabled = false;
            status.Text = disabling ? "Disabling Kevin and restoring original loader files..." : "Checking the release and installing Kevin...";
            output.Clear();
            var worker = new BackgroundWorker();
            worker.DoWork += delegate(object sender, DoWorkEventArgs e) {
                logPath = null;
                string logDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"KevinCompanion\Logs");
                try {
                    BundlePayload.CheckNoLinks(logDirectory);
                    Directory.CreateDirectory(logDirectory);
                    logPath = Path.Combine(logDirectory, "Setup-" + DateTime.UtcNow.ToString("yyyyMMddTHHmmssZ") + "-" + Guid.NewGuid().ToString("N") + ".txt");
                    File.WriteAllText(logPath, reportText, new UTF8Encoding(false));
                } catch (Exception error) { logPath = null; reportText += "Automatic report could not be created: " + error.Message + "\r\n"; }
                if (extracted == null) extracted = payload.Extract(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"KevinCompanion\Setup"));
                payload.VerifyExtracted(extracted);
                string script = Path.Combine(extracted, disabling ? "Disable-Kevin.ps1" : "Install-Kevin.ps1");
                var start = new ProcessStartInfo {
                    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
                    Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(script) + " -GamePath " + Quote(selected),
                    WorkingDirectory = extracted, UseShellExecute = false, CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden, RedirectStandardOutput = true, RedirectStandardError = true
                };
                var log = new StringBuilder(); object guard = new object();
                using (var process = new Process { StartInfo = start }) {
                    process.OutputDataReceived += delegate(object s, DataReceivedEventArgs line) { if (line.Data != null) lock (guard) log.AppendLine(line.Data); };
                    process.ErrorDataReceived += delegate(object s, DataReceivedEventArgs line) { if (line.Data != null) lock (guard) log.AppendLine(line.Data); };
                    process.Start(); process.BeginOutputReadLine(); process.BeginErrorReadLine(); process.WaitForExit();
                    reportText += log.ToString() + "\r\nExit code: " + process.ExitCode + "\r\n";
                    e.Result = new RunResult { ExitCode = process.ExitCode, Log = log.ToString() };
                }
            };
            worker.RunWorkerCompleted += delegate(object sender, RunWorkerCompletedEventArgs e) {
                busy = false; install.Enabled = disable.Enabled = browse.Enabled = guide.Enabled = game.Enabled = true;
                saveReport.Enabled = true;
                if (e.Error != null) {
                    output.Text = e.Error.ToString();
                    reportText += output.Text; PersistReport();
                    ShowFailure(output.Text); ShowReportLocation(); return;
                }
                PersistReport();
                var result = (RunResult)e.Result; output.Text = result.Log;
                if (result.ExitCode != 0) { ShowFailure(result.Log); }
                else status.Text = disabling ? "Kevin disabled. Saves, compatibility package and backups were retained." : "Kevin installed. Open the game and select Kevin Companion in your profile's Mods list.";
                ShowReportLocation();
            };
            worker.RunWorkerAsync();
        }
        private void PersistReport() {
            if (logPath == null) return;
            try { File.WriteAllText(logPath, reportText, new UTF8Encoding(false)); }
            catch (Exception error) { logPath = null; reportText += "\r\nAutomatic report could not be saved: " + error.Message; }
        }
        private void ShowReportLocation() {
            output.AppendText(logPath == null ? "\r\nUse Save setup report to keep these details; automatic logging was unavailable." : "\r\nReport saved automatically: " + logPath);
        }
        private void ShowFailure(string details) {
            bool denied = Regex.IsMatch(details, "UnauthorizedAccess|Access.*denied|permission", RegexOptions.IgnoreCase);
            administrator.Enabled = denied && !IsAdministrator();
            if (denied) status.Text = IsAdministrator() ? "Windows still blocked access. Save the report below so we can diagnose it." :
                "Windows blocked access to the game folder. Choose Retry as administrator and approve the Windows permission prompt.";
            else if (details.IndexOf("Close Subsistence", StringComparison.OrdinalIgnoreCase) >= 0)
                status.Text = "Close Subsistence, then choose Install / Update or Disable Kevin again.";
            else if (Regex.IsMatch(details, "checksum mismatch|length mismatch|version/checksum", RegexOptions.IgnoreCase)) {
                status.Text = "A file differs from the supported Alpha 68.19 release. Back up your saves and save this report. Recovery steps are shown below.";
                string recovery = "\r\n\r\nRecovery steps:\r\n" +
                    "Keep a copy of your saves and the .KevinLoader folder before restoring any files.\r\n" +
                    "For a modified game file on a fresh installation, restore its verified original backup, or use Steam > Subsistence > Properties > Installed Files > Verify integrity of game files. Then rerun Setup.\r\n" +
                    "If Kevin is already installed, or the reported file is in .KevinLoader or KevinCompanion\\Setup, share this report before restoring files so the existing installation and backups can be checked.\r\n" +
                    "Setup will not force a patch onto a different file. The report includes the expected and actual file hashes and lengths when available.";
                output.AppendText(recovery);
                if (reportText != null) { reportText += recovery; PersistReport(); }
            }
            else status.Text = "Setup did not complete. Choose Save setup report below and include it when reporting this issue.";
        }
        private static bool IsAdministrator() {
            using (var identity = WindowsIdentity.GetCurrent())
                return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
        }
        internal void ResumeElevated(string path, bool disabling) {
            if (!IsAdministrator()) throw new InvalidOperationException("Windows did not grant administrator access. Open Kevin Setup normally to try again.");
            game.Text = Path.GetFullPath(path);
            Shown += delegate { BeginInvoke(new Action(delegate { RunInstaller(disabling); })); };
        }
        private static ProcessStartInfo ElevatedStartInfo(string executable, string selected, bool disabling) {
            return new ProcessStartInfo {
                FileName = executable, UseShellExecute = true, Verb = "runas",
                Arguments = "--game-path " + Quote(selected) + " --action " + (disabling ? "disable" : "install"),
                WorkingDirectory = Path.GetDirectoryName(executable)
            };
        }
        private void RestartElevated() {
            try {
                string executable = Assembly.GetExecutingAssembly().Location;
                if (String.IsNullOrEmpty(executable)) throw new IOException("Reopen the downloaded Kevin Setup file to retry as administrator.");
                using (var process = Process.Start(ElevatedStartInfo(executable, lastGame, lastDisabling))) { }
                Close();
            } catch (Win32Exception e) {
                status.Text = e.NativeErrorCode == 1223 ? "The Windows permission prompt was cancelled. No retry was started." : "Could not restart setup: " + e.Message;
            } catch (Exception e) { status.Text = "Could not restart setup: " + e.Message; }
        }
        private static string Quote(string value) {
            // Windows argv quoting; never interpolate a path into PowerShell source code.
            return "\"" + Regex.Replace(value, "(\\\\*)\"", "$1$1\\\"").TrimEnd('\r', '\n') + new string('\\', value.Length - value.TrimEnd('\\').Length) + "\"";
        }
        private sealed class RunResult { public int ExitCode; public string Log; }
    }
}
