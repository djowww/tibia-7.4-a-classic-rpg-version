using System.Buffers.Binary;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;

namespace AntigasLauncher;

internal sealed record GuardianEndpoint(string Host, int Port);
internal sealed record GuardianIssue(string Token, int PlayersOnline, int HeartbeatSeconds);

// Talks to the game server's status port (src/protocolstatus.cpp, request 'G').
// The session token it gets is what links this launcher to the character that
// logs in; see data/lib/custom/guardian.lua on the server.
internal static class GuardianClient
{
    internal const int TokenLength = 32;
    private const int MaxDetail = 300;
    private static readonly Regex ServerPattern = new(
        @"^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*""([A-Za-z0-9.\-]{1,253}):(\d{1,5}):\d+",
        RegexOptions.Multiline | RegexOptions.CultureInvariant | RegexOptions.Compiled);
    private static readonly Regex AppNamePattern = new(
        @"^[ \t]*g_app\.setName\(\s*""([^""\\/:*?<>|]{1,80})""\s*\)",
        RegexOptions.Multiline | RegexOptions.CultureInvariant | RegexOptions.Compiled);

    // The launcher asks the same server the client logs in to: the first entry of Servers in init.lua.
    public static GuardianEndpoint? ReadEndpoint(string root)
    {
        var init = ReadInit(root);
        var start = init.IndexOf("Servers", StringComparison.Ordinal);
        if (start < 0) return null;
        var match = ServerPattern.Match(init, start);
        if (!match.Success || !int.TryParse(match.Groups[2].Value, out var port) || port is < 1 or > 65535) return null;
        return new GuardianEndpoint(match.Groups[1].Value, port);
    }

    // Name the client gives itself; it is also the name of its settings folder under %APPDATA%\OTClientV8.
    public static string? ReadClientName(string root)
    {
        var match = AppNamePattern.Match(ReadInit(root));
        return match.Success ? match.Groups[1].Value : null;
    }

    private static string ReadInit(string root)
    {
        try
        {
            var path = Path.Combine(root, "init.lua");
            return File.Exists(path) && new FileInfo(path).Length < 1024 * 1024 ? File.ReadAllText(path) : "";
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return ""; }
    }

    public static async Task<int?> GetPlayersOnlineAsync(GuardianEndpoint endpoint, CancellationToken cancellationToken)
    {
        var answer = await ExchangeAsync(endpoint, [(byte)'G', 3, 0, 0, 0], cancellationToken);
        return IsAnswer(answer, 3, 5) ? BinaryPrimitives.ReadUInt16LittleEndian(answer.AsSpan(3)) : null;
    }

    public static async Task<GuardianIssue?> IssueAsync(GuardianEndpoint endpoint, int launcherVersion, int clientVersion,
        GuardianFlags flags, string detail, CancellationToken cancellationToken)
    {
        var text = Ascii(detail);
        var body = new byte[2 + 2 + 2 + 1 + 2 + text.Length];
        body[0] = (byte)'G'; body[1] = 1;
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(2), (ushort)Math.Clamp(launcherVersion, 0, ushort.MaxValue));
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(4), (ushort)Math.Clamp(clientVersion, 0, ushort.MaxValue));
        body[6] = (byte)flags;
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(7), (ushort)text.Length);
        text.CopyTo(body, 9);
        var answer = await ExchangeAsync(endpoint, body, cancellationToken);
        if (!IsAnswer(answer, 1, 7 + TokenLength)) return null;
        var token = Encoding.ASCII.GetString(answer, 7, TokenLength);
        if (!token.All(Uri.IsHexDigit)) return null;
        return new GuardianIssue(token, BinaryPrimitives.ReadUInt16LittleEndian(answer.AsSpan(3)),
            Math.Clamp((int)BinaryPrimitives.ReadUInt16LittleEndian(answer.AsSpan(5)), 15, 600));
    }

    // True: session alive. False: the server no longer knows the token (it restarted, or the session expired).
    public static async Task<bool> HeartbeatAsync(GuardianEndpoint endpoint, string token, GuardianFlags flags, string detail,
        CancellationToken cancellationToken)
    {
        var text = Ascii(detail);
        var body = new byte[2 + 2 + TokenLength + 1 + 2 + text.Length];
        body[0] = (byte)'G'; body[1] = 2;
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(2), TokenLength);
        Encoding.ASCII.GetBytes(token, 0, TokenLength, body, 4);
        body[4 + TokenLength] = (byte)flags;
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(5 + TokenLength), (ushort)text.Length);
        text.CopyTo(body, 7 + TokenLength);
        var answer = await ExchangeAsync(endpoint, body, cancellationToken);
        if (answer.Length < 3 || answer[0] != (byte)'G' || answer[1] != 2) throw new IOException("Unexpected answer from the server.");
        return answer[2] == 0;
    }

    private static bool IsAnswer(byte[] answer, byte op, int length) =>
        answer.Length >= length && answer[0] == (byte)'G' && answer[1] == op && answer[2] == 0;

    private static byte[] Ascii(string text)
    {
        var bytes = new byte[Math.Min(text.Length, MaxDetail)];
        for (var i = 0; i < bytes.Length; i++) bytes[i] = text[i] is >= ' ' and < (char)0x7F ? (byte)text[i] : (byte)'?';
        return bytes;
    }

    private static async Task<byte[]> ExchangeAsync(GuardianEndpoint endpoint, byte[] body, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(6));
        using var client = new TcpClient { NoDelay = true };
        await client.ConnectAsync(endpoint.Host, endpoint.Port, timeout.Token);
        var stream = client.GetStream();
        // Packet: length (2 bytes), protocol 0xFF (status), then the request.
        var packet = new byte[3 + body.Length];
        BinaryPrimitives.WriteUInt16LittleEndian(packet, (ushort)(1 + body.Length));
        packet[2] = 0xFF;
        body.CopyTo(packet, 3);
        await stream.WriteAsync(packet, timeout.Token);
        var answer = new byte[64];
        var total = 0;
        while (total < answer.Length)
        {
            var read = await stream.ReadAsync(answer.AsMemory(total), timeout.Token);
            if (read == 0) break;
            total += read;
        }
        return answer[..total];
    }
}

[Flags]
internal enum GuardianFlags : byte
{
    None = 0,
    FilesOk = 1 << 0,
    FilesModified = 1 << 1,
    BotTool = 1 << 2,
    MacroTool = 1 << 3,
    Injected = 1 << 4,
    NoManifest = 1 << 5,
}
