using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

const string KeyName = "Antigas.ClientRelease.Signing.P256.v1";
const string CanonicalPrefix = "ANTIGAS-CLIENT-RELEASE-V1";
const string FilesCanonicalPrefix = "ANTIGAS-CLIENT-FILES-V1";
const string FilesManifestName = "client.files.json";
const string PinnedPublicKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAELyhqZ/vlL8gMrlo3VHBmfALsf3k/RZaJyErvum5sJjUFabJRQqVtzn4j9JqR/iYgU5VRyuKiG0tRP6pCo4btJg==";

if (args.Length == 2 && args[0] == "keygen")
{
    using var key = OpenOrCreateSigningKey();
    using var signer = new ECDsaCng(key);
    var publicKey = Convert.ToBase64String(signer.ExportSubjectPublicKeyInfo());
    File.WriteAllText(Path.GetFullPath(args[1]), publicKey + Environment.NewLine, new UTF8Encoding(false));
    Console.WriteLine("Created or opened the current-user signing key.");
    Console.WriteLine($"Public key written to: {Path.GetFullPath(args[1])}");
    Console.WriteLine("The private key remains non-exportable in the Windows user key store.");
    return;
}

if (args.Length == 5 && args[0] == "sign")
{
    if (!int.TryParse(args[1], NumberStyles.None, CultureInfo.InvariantCulture, out var version) || version < 1 || version > 1_000_000)
        throw new ArgumentException("Version must be an integer from 1 to 1000000.");
    var packagePath = Path.GetFullPath(args[2]);
    var package = args[3];
    var outputPath = Path.GetFullPath(args[4]);
    if (!string.Equals(package, Path.GetFileName(package), StringComparison.Ordinal) ||
        !string.Equals(package, $"Antigas-7.4-Update-v{version}.zip", StringComparison.Ordinal))
        throw new ArgumentException("Package name must match the selected version.");
    if (!File.Exists(packagePath)) throw new FileNotFoundException("Package not found.", packagePath);

    using var packageStream = File.OpenRead(packagePath);
    var hash = Convert.ToHexString(SHA256.HashData(packageStream)).ToLowerInvariant();
    var canonical = Encoding.UTF8.GetBytes($"{CanonicalPrefix}\n{version}\n{package}\n{hash}\n");
    using var key = OpenExistingSigningKey();
    using var signer = new ECDsaCng(key);
    var publicKey = signer.ExportSubjectPublicKeyInfo();
    if (!CryptographicOperations.FixedTimeEquals(publicKey, Convert.FromBase64String(PinnedPublicKey)))
        throw new CryptographicException("The local signing key does not match the public key pinned in the launcher.");
    var signature = Convert.ToBase64String(signer.SignData(canonical, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
    using var verifier = ECDsa.Create();
    verifier.ImportSubjectPublicKeyInfo(publicKey, out _);
    if (!verifier.VerifyData(canonical, Convert.FromBase64String(signature), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation))
        throw new CryptographicException("The generated release signature could not be verified.");
    var manifest = new ReleaseManifest(version, $"Antigas 7.4 v{version}", hash, package, "ECDSA-P256-SHA256-P1363", signature);
    var json = JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine;
    Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
    File.WriteAllText(outputPath, json, new UTF8Encoding(false));
    Console.WriteLine($"Signed release {version}; package SHA-256: {hash}");
    Console.WriteLine($"Manifest written to: {outputPath}");
    return;
}

if (args.Length == 3 && args[0] == "sign-files")
{
    // Signs the list of every file of a staged client. The launcher (ClientIntegrity.cs)
    // compares the installed client with this list before each game start.
    if (!int.TryParse(args[1], NumberStyles.None, CultureInfo.InvariantCulture, out var version) || version < 1 || version > 1_000_000)
        throw new ArgumentException("Version must be an integer from 1 to 1000000.");
    var root = Path.GetFullPath(args[2]).TrimEnd(Path.DirectorySeparatorChar);
    if (!File.Exists(Path.Combine(root, "init.lua"))) throw new DirectoryNotFoundException("The folder is not a client: init.lua is missing.");
    var files = new List<FileEntry>();
    foreach (var path in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
    {
        var relative = Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/');
        if (IsUnlisted(relative)) continue;
        using var stream = File.OpenRead(path);
        files.Add(new FileEntry(relative, stream.Length, Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant()));
    }
    files.Sort((left, right) => string.CompareOrdinal(left.path, right.path));
    var text = new StringBuilder().Append(FilesCanonicalPrefix).Append('\n').Append(version).Append('\n');
    foreach (var file in files) text.Append(file.path).Append('\n').Append(file.size).Append('\n').Append(file.sha256).Append('\n');
    var canonical = Encoding.UTF8.GetBytes(text.ToString());
    using var key = OpenExistingSigningKey();
    using var signer = new ECDsaCng(key);
    var publicKey = signer.ExportSubjectPublicKeyInfo();
    if (!CryptographicOperations.FixedTimeEquals(publicKey, Convert.FromBase64String(PinnedPublicKey)))
        throw new CryptographicException("The local signing key does not match the public key pinned in the launcher.");
    var signature = signer.SignData(canonical, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    using var verifier = ECDsa.Create();
    verifier.ImportSubjectPublicKeyInfo(publicKey, out _);
    if (!verifier.VerifyData(canonical, signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation))
        throw new CryptographicException("The generated file list signature could not be verified.");
    var manifest = new FilesManifest(version, "ECDSA-P256-SHA256-P1363", files, Convert.ToBase64String(signature));
    var outputPath = Path.Combine(root, FilesManifestName);
    File.WriteAllText(outputPath, JsonSerializer.Serialize(manifest) + Environment.NewLine, new UTF8Encoding(false));
    Console.WriteLine($"Signed the file list of client {version}: {files.Count} files.");
    Console.WriteLine($"File list written to: {outputPath}");
    return;
}

Console.Error.WriteLine("Usage:");
Console.Error.WriteLine("  ReleaseSigner keygen <public-key-output.txt>");
Console.Error.WriteLine("  ReleaseSigner sign <version> <package.zip> <package-name> <manifest-output.json>");
Console.Error.WriteLine("  ReleaseSigner sign-files <version> <client-folder>");
Environment.ExitCode = 2;

static CngKey OpenOrCreateSigningKey()
{
    try
    {
        return CngKey.Open(KeyName, CngProvider.MicrosoftSoftwareKeyStorageProvider, CngKeyOpenOptions.None);
    }
    catch (CryptographicException)
    {
        var parameters = new CngKeyCreationParameters
        {
            Provider = CngProvider.MicrosoftSoftwareKeyStorageProvider,
            KeyUsage = CngKeyUsages.Signing,
            ExportPolicy = CngExportPolicies.None,
            KeyCreationOptions = CngKeyCreationOptions.None
        };
        return CngKey.Create(CngAlgorithm.ECDsaP256, KeyName, parameters);
    }
}

// Same rule as ClientIntegrity.IsUnlisted in the launcher: files the launcher or the player creates.
static bool IsUnlisted(string relative)
{
    var first = relative.Split('/')[0];
    return relative.Equals(FilesManifestName, StringComparison.OrdinalIgnoreCase) ||
           relative.Equals("guardian.session", StringComparison.OrdinalIgnoreCase) ||
           relative.Equals("AntigasLauncher.exe", StringComparison.OrdinalIgnoreCase) ||
           first.Equals("userdata", StringComparison.OrdinalIgnoreCase) ||
           first.Equals("screenshots", StringComparison.OrdinalIgnoreCase) ||
           first.Equals("logs", StringComparison.OrdinalIgnoreCase) ||
           relative.EndsWith(".log", StringComparison.OrdinalIgnoreCase);
}

static CngKey OpenExistingSigningKey() => CngKey.Open(KeyName, CngProvider.MicrosoftSoftwareKeyStorageProvider, CngKeyOpenOptions.None);

sealed record FileEntry(string path, long size, string sha256);
sealed record FilesManifest(int version, string signatureAlgorithm, List<FileEntry> files, string signature);
sealed record ReleaseManifest(int version, string name, string sha256, string package, string signatureAlgorithm, string signature);
