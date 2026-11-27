using System.Diagnostics;
using System.Text.RegularExpressions;

namespace AntigasLauncher;

internal sealed record ScanResult(IReadOnlyList<string> BotTools, IReadOnlyList<string> MacroTools, IReadOnlyList<string> InjectedLibraries)
{
    internal static readonly ScanResult Clean = new([], [], []);
}

// Looks for programs that are known to play the game for the player. It only
// reads process names, window titles and the libraries loaded by the game:
// it never opens other programs' memory and needs no administrator rights.
// A renamed or new bot is not found here; the server's own detector is what
// judges how a character actually plays.
internal static class ProcessScanner
{
    // Process name without extension, lower case, letters and digits only.
    private static readonly (string Name, bool Prefix, string Label)[] BotProcesses =
    [
        ("elfbot", true, "ElfBot"), ("bbot", false, "BBot"), ("windbot", true, "WindBot"), ("ibot", false, "iBot"),
        ("magebot", true, "MageBot"), ("tibiaauto", true, "Tibia Auto"), ("tibiabot", true, "TibiaBot"),
        ("neobot", true, "NeoBot"), ("redbot", true, "RedBot"), ("blackd", true, "Blackd Proxy"),
        ("xenobot", true, "XenoBot"), ("rifbot", true, "RifBot"), ("candybot", true, "CandyBot"),
        ("cheatengine", true, "Cheat Engine"), ("otclientbot", true, "OTClient bot"), ("kingbot", true, "KingBot"),
    ];
    private static readonly (string Name, bool Prefix, string Label)[] MacroProcesses =
    [
        ("autohotkey", true, "AutoHotkey"), ("tinytask", true, "TinyTask"), ("macrorecorder", true, "Macro Recorder"),
        ("pulover", true, "Pulover's Macro Creator"), ("uopilot", true, "UoPilot"), ("autoit3", true, "AutoIt"),
        ("ghostmouse", true, "GhostMouse"), ("autoclicker", true, "Auto Clicker"), ("opautoclicker", true, "OP Auto Clicker"),
    ];
    private static readonly Regex BotWindow = new(
        @"\b(elfbot|bbot|windbot|magebot|xenobot|rifbot|neobot|blackd proxy|tibia ?auto|cheat engine)\b",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
    private static readonly Regex BotLibrary = new(@"bot|cheat|inject|speedhack|trainer",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

    public static ScanResult Scan(Process? game, string clientRoot)
    {
        var bots = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        var macros = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        var libraries = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        var self = Environment.ProcessId;
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    if (process.Id == self) continue;
                    var name = Normalize(process.ProcessName);
                    if (Match(BotProcesses, name) is { } bot) bots.Add(bot);
                    else if (Match(MacroProcesses, name) is { } macro) macros.Add(macro);
                    else
                    {
                        var title = process.MainWindowTitle;
                        if (title.Length > 0 && BotWindow.Match(title) is { Success: true } window) bots.Add(window.Value);
                    }
                }
                catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException) { }
            }
        }
        if (game is not null) ScanLibraries(game, clientRoot, libraries);
        return new ScanResult(bots.ToArray(), macros.ToArray(), libraries.ToArray());
    }

    private static void ScanLibraries(Process game, string clientRoot, SortedSet<string> libraries)
    {
        try
        {
            game.Refresh();
            if (game.HasExited) return;
            var root = Path.GetFullPath(clientRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            foreach (ProcessModule module in game.Modules)
            {
                using (module)
                {
                    var path = module.FileName ?? "";
                    if (path.Length == 0 || path.StartsWith(root, StringComparison.OrdinalIgnoreCase) ||
                        path.StartsWith(windows, StringComparison.OrdinalIgnoreCase)) continue;
                    var file = Path.GetFileName(path);
                    if (BotLibrary.IsMatch(file)) libraries.Add(file);
                }
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException) { }
    }

    internal static string? BotName(string processName) => Match(BotProcesses, Normalize(processName));
    internal static string? MacroName(string processName) => Match(MacroProcesses, Normalize(processName));

    internal static string Normalize(string processName)
    {
        Span<char> buffer = stackalloc char[Math.Min(processName.Length, 64)];
        var length = 0;
        foreach (var c in processName)
        {
            if (length == buffer.Length) break;
            if (char.IsAsciiLetterOrDigit(c)) buffer[length++] = char.ToLowerInvariant(c);
        }
        return new string(buffer[..length]);
    }

    internal static string? Match((string Name, bool Prefix, string Label)[] list, string normalized)
    {
        foreach (var (name, prefix, label) in list)
        {
            if (prefix ? normalized.StartsWith(name, StringComparison.Ordinal) : normalized == name) return label;
        }
        return null;
    }
}
