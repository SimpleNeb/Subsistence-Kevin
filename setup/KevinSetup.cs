using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

namespace KevinSetup {
    internal static class Program {
        [STAThread] private static void Main() {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            try {
                byte[] bytes;
                using (var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Kevin.Payload.zip")) {
                    if (resource == null) throw new InvalidDataException("Setup has no embedded release.");
                    using (var memory = new MemoryStream()) { resource.CopyTo(memory); bytes = memory.ToArray(); }
                }
                var payload = BundlePayload.Validate(bytes, BuildInfo.ZipSha256);
                Application.Run(new SetupForm(payload));
            } catch (Exception e) { MessageBox.Show(e.Message, "Kevin setup could not start", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
    }
    internal sealed class SetupForm : Form {
        private readonly BundlePayload payload;
        private readonly TextBox game = new TextBox(), output = new TextBox();
        private readonly Button install = new Button(), disable = new Button(), browse = new Button(), guide = new Button();
        private readonly Label status = new Label();
        private bool busy;
        private string extracted;
        public SetupForm(BundlePayload release) {
            payload = release; Text = "Kevin Companion Setup";
            ClientSize = new Size(650, 440); MinimumSize = new Size(666, 479);
            StartPosition = FormStartPosition.CenterScreen; Font = new Font("Segoe UI", 10);
            var heading = new Label { Text = "Kevin Companion " + payload.Version, Font = new Font(Font, FontStyle.Bold), Left = 22, Top = 20, Width = 600, Height = 28 };
            var detail = new Label { Text = "Single-player preview for Subsistence Alpha 68.19. Close the game first.", Left = 22, Top = 52, Width = 605, Height = 26 };
            var location = new Label { Text = "Subsistence folder", Left = 22, Top = 89, Width = 200, Height = 24 };
            game.SetBounds(22, 117, 494, 28); browse.SetBounds(528, 115, 100, 31); browse.Text = "Browse...";
            install.SetBounds(22, 164, 180, 39); install.Text = "Install / Update";
            disable.SetBounds(214, 164, 180, 39); disable.Text = "Disable Kevin";
            guide.SetBounds(406, 164, 222, 39); guide.Text = "Read player guide";
            status.SetBounds(22, 216, 606, 45); status.Text = "Choose Install, then select Kevin Companion in your profile's Mods list.";
            output.SetBounds(22, 269, 606, 147); output.Multiline = true; output.ReadOnly = true; output.ScrollBars = ScrollBars.Vertical;
            output.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right | AnchorStyles.Bottom;
            Controls.AddRange(new Control[] { heading, detail, location, game, browse, install, disable, guide, status, output });
            browse.Click += delegate { using (var picker = new FolderBrowserDialog()) { picker.Description = "Choose the Subsistence game folder (contains Binaries and UDKGame)"; picker.SelectedPath = game.Text; if (picker.ShowDialog(this) == DialogResult.OK) game.Text = picker.SelectedPath; } };
            install.Click += delegate { RunInstaller(false); }; disable.Click += delegate { RunInstaller(true); };
            guide.Click += delegate {
                using (var reader = new Form { Text = "Kevin player guide", Size = new Size(740, 620), StartPosition = FormStartPosition.CenterParent }) {
                    reader.Controls.Add(new TextBox { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
                        Font = new Font("Segoe UI", 10), Text = Encoding.UTF8.GetString(payload.Files["README.txt"]).Replace("\n", "\r\n").Replace("\r\r\n", "\r\n") });
                    reader.ShowDialog(this);
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
            busy = true; install.Enabled = disable.Enabled = browse.Enabled = guide.Enabled = game.Enabled = false;
            status.Text = disabling ? "Disabling Kevin and restoring original loader files..." : "Checking the release and installing Kevin...";
            output.Clear();
            var worker = new BackgroundWorker();
            worker.DoWork += delegate(object sender, DoWorkEventArgs e) {
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
                    e.Result = new RunResult { ExitCode = process.ExitCode, Log = log.ToString() };
                }
            };
            worker.RunWorkerCompleted += delegate(object sender, RunWorkerCompletedEventArgs e) {
                busy = false; install.Enabled = disable.Enabled = browse.Enabled = guide.Enabled = game.Enabled = true;
                if (e.Error != null) { output.Text = e.Error.Message; status.Text = "Setup did not complete. See the error below."; return; }
                var result = (RunResult)e.Result; output.Text = result.Log;
                if (result.ExitCode != 0) { status.Text = "Setup did not complete. See the error below. If access was denied, close setup and use Run as administrator."; }
                else status.Text = disabling ? "Kevin disabled. Saves, compatibility package and backups were retained." : "Kevin installed. Open the game and select Kevin Companion in your profile's Mods list.";
            };
            worker.RunWorkerAsync();
        }
        private static string Quote(string value) {
            // Windows argv quoting; never interpolate a path into PowerShell source code.
            return "\"" + Regex.Replace(value, "(\\\\*)\"", "$1$1\\\"").TrimEnd('\r', '\n') + new string('\\', value.Length - value.TrimEnd('\\').Length) + "\"";
        }
        private sealed class RunResult { public int ExitCode; public string Log; }
    }
}
