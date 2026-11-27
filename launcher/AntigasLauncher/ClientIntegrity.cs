using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AntigasLauncher;

internal enum IntegrityState { Verified, Modified, NoManifest }

internal sealed record IntegrityResult(IntegrityState State, int FileCount, IReadOnlyList<string> Problems);

internal sealed class ClientFileEntry
{
    [JsonPropertyName("path")] public string Path { get; init; } = "";
    [JsonPropertyName("size")] public long Size { get; init; }
    [JsonPropertyName("sha256")] public string Sha256 { get; init; } = "";
}

internal sealed class ClientFilesManifest
{
    [JsonPropertyName("version")] public int Version { get; init; }
    [JsonPropertyName("signatureAlgorithm")] public string SignatureAlgorithm { get; init; } = "";
    [JsonPropertyName("files")] public List<ClientFileEntry> Files { get; init; } = [];
    [JsonPropertyName("signature")] public string Signature { get; init; } = "";
}

// Compares the installed client with client.files.json, the list of every
// shipped file signed by the release publisher (tools/ReleaseSigner, "sign-files").
// A changed file, or a script, library or archive that the list does not
// name, means the client is not the published one.
internal static class ClientIntegrity
{
    internal const string ManifestName = "client.files.json";
    internal const string SessionFileName = "guardian.session";
    internal const string CanonicalPrefix = "ANTIGAS-CLIENT-FILES-V1";
    private const string SignatureAlgorithm = "ECDSA-P256-SHA256-P1363";
    private const int MaxProblems = 8;
    private const int MaxFiles = 20000;

    // What can change how the client behaves when dropped into its folders.
    private static readonly HashSet<string> CodeExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".lua", ".luac", ".otmod", ".otui", ".otml", ".otfont", ".otps", ".dll", ".exe", ".zip", ".spr", ".dat", ".bat", ".cmd", ".js",
    };

    internal static string Canonical(int version, IEnumerable<ClientFileEntry> files)
    {
        var text = new StringBuilder().Append(CanonicalPrefix).Append('\n').Append(version).Append('\n');
        foreach (var file in files.OrderBy(file => file.Path, StringComparer.Ordinal))
            text.Append(file.Path).Append('\n').Append(file.Size).Append('\n').Append(file.Sha256.ToLowerInvariant()).Append('\n');
        return text.ToString();
    }

    // Files the launcher or the player legitimately creates next to the client.
    internal static bool IsUnlisted(string relative)
    {
        var first = relative.Split('/')[0];
        return relative.Equals(ManifestName, StringComparison.OrdinalIgnoreCase) ||
               relative.Equals(SessionFileName, StringComparison.OrdinalIgnoreCase) ||
               relative.Equals("AntigasLauncher.exe", StringComparison.OrdinalIgnoreCase) ||
               first.Equals("userdata", StringComparison.OrdinalIgnoreCase) ||
               first.Equals("screenshots", StringComparison.OrdinalIgnoreCase) ||
               first.Equals("logs", StringComparison.OrdinalIgnoreCase) ||
               relative.EndsWith(".log", StringComparison.OrdinalIgnoreCase);
    }

    public static IntegrityResult Verify(string root, int installedVersion, string? settingsDirectory,
        IProgress<(int Done, int Total)>? progress, CancellationToken cancellationToken) =>
        Verify(root, installedVersion, settingsDirectory, progress, cancellationToken, ReleaseService.PublicKeyBase64);

    internal static IntegrityResult Verify(string root, int installedVersion, string? settingsDirectory,
        IProgress<(int Done, int Total)>? progress, CancellationToken cancellationToken, string publicKeyBase64)
    {
        root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
        var manifestPath = Path.Combine(root, ManifestName);
        if (!File.Exists(manifestPath)) return new IntegrityResult(IntegrityState.NoManifest, 0, []);

        ClientFilesManifest manifest;
        try
        {
            if (new FileInfo(manifestPath).Length > 8 * 1024 * 1024) throw new InvalidDataException("too large");
            manifest = JsonSerializer.Deserialize<ClientFilesManifest>(File.ReadAllBytes(manifestPath)) ?? throw new InvalidDataException("empty");
            if (manifest.Files.Count is < 1 or > MaxFiles) throw new InvalidDataException("file count");
            if (!string.Equals(manifest.SignatureAlgorithm, SignatureAlgorithm, StringComparison.Ordinal)) throw new InvalidDataException("algorithm");
            foreach (var file in manifest.Files)
            {
                if (!IsSafeRelativePath(file.Path) || file.Size < 0 || file.Sha256.Length != 64 || !file.Sha256.All(Uri.IsHexDigit))
                    throw new InvalidDataException("entry");
            }
            var signature = Convert.FromBase64String(manifest.Signature);
            using var verifier = ECDsa.Create();
            verifier.ImportSubjectPublicKeyInfo(Convert.FromBase64String(publicKeyBase64), out _);
            if (signature.Length != 64 || !verifier.VerifyData(Encoding.UTF8.GetBytes(Canonical(manifest.Version, manifest.Files)),
                    signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation))
                throw new CryptographicException("signature");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException or FormatException or InvalidDataException or CryptographicException)
        {
            return new IntegrityResult(IntegrityState.Modified, 0, [ManifestName + " (signature)"]);
        }

        var problems = new List<string>();
        if (manifest.Version != installedVersion) problems.Add($"{ManifestName} (v{manifest.Version}, client v{installedVersion})");

        var listed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var done = 0;
        foreach (var file in manifest.Files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            listed.Add(file.Path);
            var path = Path.Combine(root, file.Path.Replace('/', Path.DirectorySeparatorChar));
            try
            {
                var info = new FileInfo(path);
                if (!info.Exists || info.Length != file.Size || (info.Attributes & FileAttributes.ReparsePoint) != 0) problems.Add(file.Path);
                else
                {
                    using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 128 * 1024, FileOptions.SequentialScan);
                    if (!CryptographicOperations.FixedTimeEquals(SHA256.HashData(stream), Convert.FromHexString(file.Sha256))) problems.Add(file.Path);
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { problems.Add(file.Path); }
            progress?.Report((++done, manifest.Files.Count));
        }

        foreach (var relative in EnumerateFiles(root))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (listed.Contains(relative) || IsUnlisted(relative)) continue;
            if (CodeExtensions.Contains(Path.GetExtension(relative))) problems.Add("+" + relative);
        }

        // The client also loads files from its settings folder, where they override the shipped ones.
        // Settings and hotkeys (.otml) and the minimap live there; scripts, interface files and libraries do not.
        if (settingsDirectory is not null && Directory.Exists(settingsDirectory))
        {
            foreach (var relative in EnumerateFiles(settingsDirectory))
            {
                cancellationToken.ThrowIfCancellationRequested();
                var extension = Path.GetExtension(relative);
                if (!extension.Equals(".otml", StringComparison.OrdinalIgnoreCase) && CodeExtensions.Contains(extension))
                    problems.Add("+settings/" + relative);
            }
        }

        var state = problems.Count == 0 ? IntegrityState.Verified : IntegrityState.Modified;
        return new IntegrityResult(state, manifest.Files.Count, problems.Take(MaxProblems).ToArray());
    }

    private static IEnumerable<string> EnumerateFiles(string root)
    {
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
        var count = 0;
        foreach (var path in Directory.EnumerateFiles(root, "*", options))
        {
            if (++count > MaxFiles * 4) yield break;
            yield return Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/');
        }
    }

    private static bool IsSafeRelativePath(string path) =>
        path.Length is > 0 and < 260 && !path.StartsWith('/') && !path.Contains('\\') && !path.Contains(':') &&
        path.Split('/').All(part => part.Length > 0 && part is not ("." or ".."));
}
