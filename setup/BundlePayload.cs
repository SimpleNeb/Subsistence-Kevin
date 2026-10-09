using System;
using System.IO;
using System.IO.Compression;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace KevinSetup {
    public sealed class BundlePayload {
        public readonly Dictionary<string, byte[]> Files;
        public readonly string Version;
        public readonly string BuildId;
        private BundlePayload(Dictionary<string, byte[]> files, string version, string buildId) {
            Files = files; Version = version; BuildId = buildId;
        }
        public static string Hash(byte[] bytes) {
            using (var sha = SHA256.Create()) { return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant(); }
        }
        public static string HashFile(string path) {
            using (var stream = File.OpenRead(path)) using (var sha = SHA256.Create()) {
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
            }
        }
        public static BundlePayload Validate(byte[] zipBytes, string expectedHash) {
            if (!Regex.IsMatch(expectedHash, "^[a-f0-9]{64}$") || Hash(zipBytes) != expectedHash)
                throw new InvalidDataException("The embedded release archive failed its checksum.");
            if (zipBytes.Length > 32 * 1024 * 1024) throw new InvalidDataException("Release archive exceeds the bounded size limit.");
            var allowed = new HashSet<string>(StringComparer.Ordinal) {
                "Install-Kevin.ps1", "Disable-Kevin.ps1", "KevinLoader.Common.ps1", "Install Kevin.cmd", "Disable Kevin.cmd",
                "README.txt", "PLAYER-GUIDE.txt", "VALIDATION.txt", "manifest.json", "CHECKSUMS.sha256", "files/KevinCompanion.u", "files/mod.json",
                "patches/ColdGame.u.json", "patches/ColdGame.u.bin", "patches/ColdIntroLogos.udk.json", "patches/ColdIntroLogos.udk.bin",
                "patches/ColdMenuMap.udk.json", "patches/ColdMenuMap.udk.bin", "patches/ColdMap1.udk.json", "patches/ColdMap1.udk.bin"
            };
            var files = new Dictionary<string, byte[]>(StringComparer.Ordinal);
            string root = null;
            long total = 0;
            using (var memory = new MemoryStream(zipBytes, false)) using (var zip = new ZipArchive(memory, ZipArchiveMode.Read)) {
                if (zip.Entries.Count != allowed.Count && zip.Entries.Count != allowed.Count - 1)
                    throw new InvalidDataException("Unexpected release contents.");
                foreach (var entry in zip.Entries) {
                    string full = entry.FullName;
                    int slash = full.IndexOf('/');
                    if (slash < 1 || full.IndexOf('\\') >= 0 || full.IndexOf(':') >= 0)
                        throw new InvalidDataException("Unsafe archive path.");
                    string thisRoot = full.Substring(0, slash), name = full.Substring(slash + 1);
                    if (!Regex.IsMatch(thisRoot, "^Kevin-Companion-[A-Za-z0-9_.-]+-Alpha68\\.19$") ||
                        (root != null && root != thisRoot) || !allowed.Contains(name) || files.ContainsKey(name))
                        throw new InvalidDataException("Unexpected or duplicate archive path: " + full);
                    root = thisRoot;
                    // Reject Unix symlinks and Windows reparse entries rather than following them.
                    int type = (entry.ExternalAttributes >> 16) & 0xF000;
                    if ((type != 0 && type != 0x8000) || (entry.ExternalAttributes & 0x400) != 0)
                        throw new InvalidDataException("Linked archive entries are unsupported.");
                    if (entry.Length <= 0 || entry.Length > 16 * 1024 * 1024 || (total += entry.Length) > 64 * 1024 * 1024)
                        throw new InvalidDataException("Release content exceeds the bounded size limit.");
                    using (var input = entry.Open()) using (var output = new MemoryStream()) {
                        byte[] buffer = new byte[8192]; int n;
                        while ((n = input.Read(buffer, 0, buffer.Length)) > 0) {
                            if (output.Length + n > entry.Length) throw new InvalidDataException("Archive entry length mismatch.");
                            output.Write(buffer, 0, n);
                        }
                        if (output.Length != entry.Length) throw new InvalidDataException("Truncated archive entry.");
                        files.Add(name, output.ToArray());
                    }
                }
            }
            string checksums = Encoding.ASCII.GetString(files["CHECKSUMS.sha256"]);
            var checkedNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (string line in checksums.Split(new char[] {'\n'}, StringSplitOptions.RemoveEmptyEntries)) {
                Match match = Regex.Match(line.TrimEnd('\r'), "^([a-f0-9]{64})  (.+)$");
                string name = match.Groups[2].Value;
                if (!match.Success || name == "CHECKSUMS.sha256" || !files.ContainsKey(name) || !checkedNames.Add(name) ||
                    Hash(files[name]) != match.Groups[1].Value) throw new InvalidDataException("Release file checksum mismatch.");
            }
            if (checkedNames.Count != files.Count - 1) throw new InvalidDataException("Incomplete release checksum list.");
            var json = new JavaScriptSerializer();
            var manifest = json.Deserialize<Dictionary<string, object>>(Encoding.UTF8.GetString(files["manifest.json"]));
            if (Text(manifest, "format") != "kevin-loader-v1" || Text(manifest, "releaseStatus") != "VALIDATED" ||
                Text(manifest, "nativeModUuid") != "20b4beb3-1cc9-48e8-bcfc-c41410f6fdbf")
                throw new InvalidDataException("Setup accepts only a validated Kevin public release.");
            foreach (string key in manifest.Keys) if (key.StartsWith("candidate", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Private development fields cannot enter setup.");
            string version = Text(manifest, "companionVersion"), buildId = Text(manifest, "buildId");
            if (!Regex.IsMatch(version, "^[A-Za-z0-9_.-]{1,80}$") || !Regex.IsMatch(buildId, "^[A-Za-z0-9_.-]{1,80}$"))
                throw new InvalidDataException("Invalid release identity.");
            if (root != "Kevin-Companion-" + version + "-Alpha68.19") throw new InvalidDataException("Archive version mismatch.");
            bool needsGuide = version.StartsWith("0.2.", StringComparison.Ordinal);
            if (files.ContainsKey("PLAYER-GUIDE.txt") != needsGuide || files.Count != allowed.Count - (needsGuide ? 0 : 1))
                throw new InvalidDataException("Player guide does not match this release format.");
            if (needsGuide) {
                byte[] guide = files["PLAYER-GUIDE.txt"];
                string text = new UTF8Encoding(false, true).GetString(guide);
                if (guide.Length > 1024 * 1024 || String.IsNullOrWhiteSpace(text) || text.IndexOf('\0') >= 0)
                    throw new InvalidDataException("The player guide must be bounded, nonempty UTF-8 text.");
            }
            return new BundlePayload(files, version, buildId);
        }
        private static string Text(Dictionary<string, object> json, string key) {
            object value; return json.TryGetValue(key, out value) ? value as string : null;
        }
        public static void CheckNoLinks(string path) {
            var current = new DirectoryInfo(Path.GetFullPath(path));
            while (current != null) {
                if (current.Exists && (current.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Linked setup directories are unsupported: " + current.FullName);
                current = current.Parent;
            }
        }
        public string Extract(string parent) {
            parent = Path.GetFullPath(parent);
            CheckNoLinks(parent);
            Directory.CreateDirectory(parent);
            string destination = Path.Combine(parent, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(destination);
            foreach (var entry in Files) {
                string path = Path.GetFullPath(Path.Combine(destination, entry.Key.Replace('/', Path.DirectorySeparatorChar)));
                if (!path.StartsWith(destination + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("Extraction left its intended directory.");
                CheckNoLinks(Path.GetDirectoryName(path));
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                using (var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write)) file.Write(entry.Value, 0, entry.Value.Length);
                if (HashFile(path) != Hash(entry.Value)) throw new IOException("Extracted file changed: " + entry.Key);
            }
            return destination;
        }
        public void VerifyExtracted(string directory) {
            CheckNoLinks(directory);
            foreach (var entry in Files) {
                string path = Path.Combine(directory, entry.Key.Replace('/', Path.DirectorySeparatorChar));
                if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0 || HashFile(path) != Hash(entry.Value))
                    throw new IOException("A setup file changed before execution. Close and reopen setup.");
            }
        }
    }
}
