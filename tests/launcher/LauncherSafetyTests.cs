using AntigasLauncher;

const int limit = 65536;
var accepted = Enumerable.Range(0, limit).Select(i => (byte)i).ToArray();
await using (var stream = new MemoryStream(accepted))
{
    var read = await BoundedContentReader.ReadAsync(stream, limit, CancellationToken.None);
    if (!read.SequenceEqual(accepted)) throw new InvalidOperationException("The exact-limit body changed while reading.");
}

await using (var stream = new MemoryStream(new byte[limit + 1]))
{
    try
    {
        await BoundedContentReader.ReadAsync(stream, limit, CancellationToken.None);
        throw new InvalidOperationException("An oversized body was accepted.");
    }
    catch (InvalidDataException)
    {
    }
}

await using (var input = new MemoryStream(accepted))
await using (var output = new MemoryStream())
{
    var copied = BoundedStreamCopy.Copy(input, output, limit);
    if (copied != limit || !output.ToArray().SequenceEqual(accepted))
        throw new InvalidOperationException("The exact-limit stream copy changed the content.");
}

await using (var input = new MemoryStream(new byte[limit + 1]))
await using (var output = new MemoryStream())
{
    try
    {
        BoundedStreamCopy.Copy(input, output, limit);
        throw new InvalidOperationException("An oversized stream copy was accepted.");
    }
    catch (InvalidDataException)
    {
        if (output.Length > limit) throw new InvalidOperationException("The stream copy wrote beyond its configured limit.");
    }
}

var manifest = new ReleaseManifest { Version = 54, Package = "Antigas-7.4-Update-v54.zip" };
var stagingBase = new Uri("https://tibia74.tech/staging/v54/");
var stagingPackage = ReleaseService.ResolvePackageUri(manifest, stagingBase);
if (stagingPackage.AbsoluteUri != "https://tibia74.tech/staging/v54/Antigas-7.4-Update-v54.zip")
    throw new InvalidOperationException("The signed package must resolve beside the staging manifest.");
var stagingSubdomainPackage = ReleaseService.ResolvePackageUri(manifest, new Uri("https://staging.tibia74.tech/releases/v54/"));
if (stagingSubdomainPackage.AbsoluteUri != "https://staging.tibia74.tech/releases/v54/Antigas-7.4-Update-v54.zip")
    throw new InvalidOperationException("An official staging subdomain must remain usable.");
if (!ReleaseService.IsStagingManifestUri(new Uri("https://tibia74.tech/staging/v54/client-release.json")) ||
    !ReleaseService.IsStagingManifestUri(new Uri("https://staging.tibia74.tech/client-release.json")))
    throw new InvalidOperationException("Supported staging manifest locations must be accepted.");
if (ReleaseService.IsStagingManifestUri(new Uri("https://tibia74.tech/client-release.json")) ||
    ReleaseService.IsStagingManifestUri(new Uri("https://downloads.tibia74.tech/client-release.json")) ||
    ReleaseService.IsStagingManifestUri(new Uri("https://tibia74.tech/staging/client-release.json?cache=1")) ||
    ReleaseService.IsStagingManifestUri(new Uri("https://user@staging.tibia74.tech/client-release.json")) ||
    ReleaseService.IsStagingManifestUri(new Uri("https://staging.tibia74.tech:444/client-release.json")) ||
    ReleaseService.IsStagingManifestUri(new Uri("https://staging.tibia74.tech/client-release.json#fragment")))
    throw new InvalidOperationException("Production, unmarked subdomains, or credential/port/query/fragment-based manifest URLs must not count as staging.");

foreach (var unsafeBase in new[]
{
    new Uri("http://tibia74.tech/staging/v54/"),
    new Uri("https://attacker.example/staging/v54/"),
    new Uri("https://evil-tibia74.tech/staging/v54/"),
    new Uri("https://tibia74.tech.attacker.example/staging/v54/"),
    new Uri("https://user@tibia74.tech/staging/v54/"),
    new Uri("https://tibia74.tech:444/staging/v54/"),
    new Uri("https://tibia74.tech/staging/v54?redirect=1"),
    new Uri("https://tibia74.tech/staging/v54"),
})
{
    try
    {
        ReleaseService.ResolvePackageUri(manifest, unsafeBase);
        throw new InvalidOperationException("An unsafe staging package base was accepted: " + unsafeBase);
    }
    catch (InvalidDataException)
    {
    }
}

try
{
    ReleaseService.ResolvePackageUri(new ReleaseManifest { Version = 54, Package = "../outside.zip" }, stagingBase);
    throw new InvalidOperationException("A package path outside the signed version name was accepted.");
}
catch (InvalidDataException)
{
}

var repoRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../.."));
var snapshotRoot = Path.Combine(repoRoot, "client");
var currentRelease = ReleaseService.ReadAndVerifyManifest(Path.Combine(repoRoot, "site", "client-release.json"));
var integratedRoot = Path.Combine(Path.GetTempPath(), "antigas-client-overlay-test-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(integratedRoot);
try
{
    File.WriteAllText(Path.Combine(integratedRoot, "init.lua"), "APP_VERSION = 66\n");
    File.WriteAllText(Path.Combine(integratedRoot, "client.version"), "66\n");
    File.WriteAllText(Path.Combine(integratedRoot, "Antigas_gl.exe"), "INERT TEST FILE; NEVER EXECUTE");
    File.Copy(Path.Combine(snapshotRoot, "init.lua"), Path.Combine(integratedRoot, "init.lua"), true);
    var snapshotMarker = Path.Combine(snapshotRoot, "client.version");
    if (File.Exists(snapshotMarker)) File.Copy(snapshotMarker, Path.Combine(integratedRoot, "client.version"), true);
    var integratedVersion = ClientPackage.ReadInstalledVersion(integratedRoot);
    if (integratedVersion != currentRelease.Version || !ClientPackage.HasRunnableClient(integratedRoot))
        throw new InvalidOperationException($"Snapshot overlay was identified as v{integratedVersion} instead of published v{currentRelease.Version}.");
}
finally
{
    foreach (var file in new[] { "init.lua", "client.version", "Antigas_gl.exe" }) File.Delete(Path.Combine(integratedRoot, file));
    Directory.Delete(integratedRoot);
}

// An update removes the files of the DirectX client that is no longer shipped, and nothing else.
var obsoleteRoot = Path.Combine(Path.GetTempPath(), "antigas-obsolete-test-" + Guid.NewGuid().ToString("N"));
try
{
    var obsoleteStage = Path.Combine(obsoleteRoot, "stage");
    var obsoleteInstall = Path.Combine(obsoleteRoot, "install");
    Directory.CreateDirectory(obsoleteStage);
    Directory.CreateDirectory(Path.Combine(obsoleteInstall, "data"));
    File.WriteAllText(Path.Combine(obsoleteStage, "init.lua"), "APP_VERSION = 77\n");
    File.WriteAllText(Path.Combine(obsoleteStage, "client.version"), "77\n");
    File.WriteAllText(Path.Combine(obsoleteStage, "Antigas_gl.exe"), "INERT TEST FILE; NEVER EXECUTE");
    File.WriteAllText(Path.Combine(obsoleteStage, "AntigasLauncher.exe"), "INERT TEST FILE; NEVER EXECUTE");
    File.WriteAllText(Path.Combine(obsoleteStage, "libEGL.dll"), "still shipped in this test");
    string[] removed = { "Antigas_dx.exe", "libGLESv2.dll", "d3dcompiler_46.dll" };
    string[] kept = { "libEGL.dll", "my-notes.txt", Path.Combine("data", "Antigas_dx.exe") };
    foreach (var name in removed.Concat(kept)) File.WriteAllText(Path.Combine(obsoleteInstall, name), "old " + name);
    var obsoleteBackup = ClientPackage.ApplyStagedUpdate(obsoleteStage, obsoleteInstall, 77, new Progress<int>(), Path.Combine(obsoleteRoot, "backups"));
    foreach (var name in removed)
    {
        if (File.Exists(Path.Combine(obsoleteInstall, name))) throw new InvalidOperationException("An obsolete client file was left behind: " + name);
        if (File.ReadAllText(Path.Combine(obsoleteBackup, name)) != "old " + name) throw new InvalidOperationException("An obsolete client file was removed without a backup: " + name);
    }
    foreach (var name in kept)
        if (!File.Exists(Path.Combine(obsoleteInstall, name))) throw new InvalidOperationException("The update removed a file it should keep: " + name);
    if (File.ReadAllText(Path.Combine(obsoleteInstall, "libEGL.dll")) != "still shipped in this test") throw new InvalidOperationException("A shipped file was not updated.");
}
finally
{
    if (Directory.Exists(obsoleteRoot)) Directory.Delete(obsoleteRoot, true);
}

// Guardian: signed client file list, bot tool names, server address and news headlines.
var guardianRoot = Path.Combine(Path.GetTempPath(), "antigas-guardian-" + Guid.NewGuid().ToString("N"));
try
{
    var client = Path.Combine(guardianRoot, "client");
    var settings = Path.Combine(guardianRoot, "settings");
    Directory.CreateDirectory(Path.Combine(client, "modules", "game_x"));
    Directory.CreateDirectory(settings);
    File.WriteAllText(Path.Combine(client, "init.lua"),
        "g_app.setName(\"Tibia 7.4 Test\")\nAPP_VERSION = 90\nServers = {\n--  Old = \"old.example.org:7171:772\",\n Main = \"play.example.org:7172:772\"\n}\n");
    File.WriteAllText(Path.Combine(client, "modules", "game_x", "x.lua"), "print('x')");
    File.WriteAllText(Path.Combine(client, "Antigas_gl.exe"), "INERT TEST FILE; NEVER EXECUTE");
    File.WriteAllText(Path.Combine(settings, "config.otml"), "settings");
    using var guardianKey = System.Security.Cryptography.ECDsa.Create(System.Security.Cryptography.ECCurve.NamedCurves.nistP256);
    var guardianPublic = Convert.ToBase64String(guardianKey.ExportSubjectPublicKeyInfo());
    void SignFiles(int version, System.Security.Cryptography.ECDsa key)
    {
        var entries = Directory.EnumerateFiles(client, "*", SearchOption.AllDirectories)
            .Select(path => (Path: path, Relative: Path.GetRelativePath(client, path).Replace(Path.DirectorySeparatorChar, '/')))
            .Where(file => !ClientIntegrity.IsUnlisted(file.Relative))
            .Select(file => new ClientFileEntry
            {
                Path = file.Relative, Size = new FileInfo(file.Path).Length,
                Sha256 = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(file.Path))).ToLowerInvariant(),
            }).ToList();
        var signature = key.SignData(System.Text.Encoding.UTF8.GetBytes(ClientIntegrity.Canonical(version, entries)),
            System.Security.Cryptography.HashAlgorithmName.SHA256, System.Security.Cryptography.DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        File.WriteAllText(Path.Combine(client, ClientIntegrity.ManifestName), System.Text.Json.JsonSerializer.Serialize(new ClientFilesManifest
        {
            Version = version, SignatureAlgorithm = "ECDSA-P256-SHA256-P1363", Files = entries, Signature = Convert.ToBase64String(signature),
        }));
    }
    IntegrityResult Check() => ClientIntegrity.Verify(client, 90, settings, null, CancellationToken.None, guardianPublic);
    void Expect(IntegrityState state, string? problem, string scenario)
    {
        var result = Check();
        if (result.State != state || (problem is not null && !result.Problems.Contains(problem)))
            throw new InvalidOperationException($"Guardian file check, {scenario}: got {result.State} [{string.Join(", ", result.Problems)}].");
    }

    Expect(IntegrityState.NoManifest, null, "install without a file list");
    SignFiles(90, guardianKey);
    Expect(IntegrityState.Verified, null, "untouched client");
    if (Check().FileCount != 3) throw new InvalidOperationException("The signed file list should name the three shipped files.");

    // Files the player or the launcher creates do not count.
    Directory.CreateDirectory(Path.Combine(client, "userdata"));
    File.WriteAllText(Path.Combine(client, "userdata", "notes.lua"), "-- mine");
    File.WriteAllText(Path.Combine(client, "notes.txt"), "mine");
    File.WriteAllText(Path.Combine(client, ClientIntegrity.SessionFileName), new string('a', 32));
    File.WriteAllText(Path.Combine(client, "AntigasLauncher.exe"), "INERT TEST FILE; NEVER EXECUTE");
    Expect(IntegrityState.Verified, null, "player and launcher files");

    File.WriteAllText(Path.Combine(client, "modules", "game_x", "x.lua"), "print('y')");
    Expect(IntegrityState.Modified, "modules/game_x/x.lua", "edited script of the same size");
    File.WriteAllText(Path.Combine(client, "modules", "game_x", "x.lua"), "print('x')");

    Directory.CreateDirectory(Path.Combine(client, "modules", "game_bot"));
    File.WriteAllText(Path.Combine(client, "modules", "game_bot", "bot.lua"), "-- bot");
    Expect(IntegrityState.Modified, "+modules/game_bot/bot.lua", "script added to the client");
    Directory.Delete(Path.Combine(client, "modules", "game_bot"), true);

    Directory.CreateDirectory(Path.Combine(settings, "modules", "game_x"));
    File.WriteAllText(Path.Combine(settings, "modules", "game_x", "x.lua"), "-- override");
    Expect(IntegrityState.Modified, "+settings/modules/game_x/x.lua", "script overriding from the settings folder");
    Directory.Delete(Path.Combine(settings, "modules"), true);
    Expect(IntegrityState.Verified, null, "client restored");

    if (ClientIntegrity.Verify(client, 91, settings, null, CancellationToken.None, guardianPublic).State != IntegrityState.Modified)
        throw new InvalidOperationException("A file list of another client version was accepted.");
    using (var otherKey = System.Security.Cryptography.ECDsa.Create(System.Security.Cryptography.ECCurve.NamedCurves.nistP256))
    {
        SignFiles(90, otherKey);
        Expect(IntegrityState.Modified, ClientIntegrity.ManifestName + " (signature)", "file list signed with another key");
    }

    var endpoint = GuardianClient.ReadEndpoint(client);
    if (endpoint is not { Host: "play.example.org", Port: 7172 }) throw new InvalidOperationException("The launcher read the wrong game server from init.lua.");
    if (GuardianClient.ReadClientName(client) != "Tibia 7.4 Test") throw new InvalidOperationException("The launcher read the wrong client name from init.lua.");

    foreach (var name in new[] { "ElfBot NG", "BBot", "WindBot_x64", "cheatengine-x86_64" })
        if (ProcessScanner.BotName(name) is null) throw new InvalidOperationException("A known bot was not recognized: " + name);
    foreach (var name in new[] { "AutoHotkeyU64", "TinyTask" })
        if (ProcessScanner.MacroName(name) is null || ProcessScanner.BotName(name) is not null) throw new InvalidOperationException("A macro tool was not recognized as such: " + name);
    foreach (var name in new[] { "chrome", "Discord", "Rabbot", "Antigas_gl", "explorer", "ibottle" })
        if (ProcessScanner.BotName(name) is not null || ProcessScanner.MacroName(name) is not null) throw new InvalidOperationException("An ordinary program was flagged: " + name);

    var headlines = NewsService.Parse(System.Text.Encoding.UTF8.GetBytes(
        "[{\"id\":\"a\",\"date\":\"2026-11-27\",\"title\":\"Day and night.\",\"changes\":[]},{\"date\":\"bad\",\"title\":\"  \"},{\"date\":\"2026-11-24\",\"title\":\"Game Wiki\"}]"));
    if (headlines.Count != 2 || headlines[0] is not { Date: "27 November 2026", Title: "Day and night" } || headlines[1].Title != "Game Wiki")
        throw new InvalidOperationException("The news headlines were not read as expected.");
}
finally
{
    if (Directory.Exists(guardianRoot)) Directory.Delete(guardianRoot, true);
}

Console.WriteLine("Launcher bounded I/O, staging URL, snapshot overlay and Guardian regression tests passed");
