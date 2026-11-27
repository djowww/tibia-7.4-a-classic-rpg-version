using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Reflection;
using System.Text.Json;
using System.Windows.Forms;

namespace AntigasLauncher;

internal enum CheckState { Waiting, Running, Passed, Failed }

// "Watchtower": the wall, the torches and Play on the left; Guardian (the
// anti-bot checks) and the latest news on the right.
internal sealed class LauncherForm : Form
{
    private const int LogicalWidth = 960, LogicalHeight = 500, SceneWidth = 588;
    private const string WebsiteUrl = "https://tibia74.tech/";
    private const string DiscordUrl = "https://discord.gg/CVneyh53mZ";
    private const int FilesCheck = 0, ToolsCheck = 1, TokenCheck = 2, ServerCheck = 3;

    private enum Phase { Busy, Ready, NeedsRepair, Blocked, Running }

    private sealed class Check(string title, string text)
    {
        public string Title { get; } = title;
        public string Text { get; set; } = text;
        public CheckState State { get; set; }
    }

    private static readonly int LauncherVersion = ReadLauncherVersion();

    private readonly string _root = Path.GetFullPath(AppContext.BaseDirectory).TrimEnd(Path.DirectorySeparatorChar);
    private readonly CancellationTokenSource _lifetime = new();
    private readonly GoldButton _play = new();
    private readonly System.Windows.Forms.Timer _animation = new() { Interval = 140 };
    private readonly System.Windows.Forms.Timer _serverPoll = new() { Interval = 60_000 };
    private readonly List<(RectangleF Area, Action Action)> _links = [];
    private readonly Check[] _checks =
    [
        new("Client files", "Every file is compared with the official release"),
        new("Known bot tools", "Looks for bots and injectors running on this computer"),
        new("Session token", "Issued when you press Play"),
        new("Server detector", "Watches play patterns in game"),
    ];

    private Bitmap? _backdrop;
    private int _frame;
    private Phase _phase = Phase.Busy;
    private string _status = "Checking for updates";
    private string _guardianLine = "Standing by";
    private double _progress;
    private bool? _serverOnline;
    private int _playersOnline;
    private IReadOnlyList<NewsItem> _news = [new NewsItem("", "Tibia 7.4, a classic RPG version")];
    private int _newsIndex;
    private int _installedVersion;
    private GuardianEndpoint? _endpoint;
    private IntegrityResult _integrity = new(IntegrityState.NoManifest, 0, []);
    private ScanResult _scan = ScanResult.Clean;
    private GuardianFlags _reported;
    private Process? _game;
    private bool _working;

    public LauncherForm(string[] args)
    {
        Text = "Tibia 7.4 Launcher";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        AutoScaleMode = AutoScaleMode.None;
        BackColor = WatchtowerArt.Night;
        try { if (Environment.ProcessPath is { } path) Icon = Icon.ExtractAssociatedIcon(path); } catch (Exception ex) when (ex is IOException or ArgumentException) { }
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);

        _play.Text = "Play";
        _play.Enabled = false;
        _play.AccessibleName = "Play";
        _play.Click += async (_, _) => await OnPrimaryAsync();
        Controls.Add(_play);
        AcceptButton = _play;
        ApplyScale();

        _animation.Tick += (_, _) => { _frame++; Invalidate(); };
        _serverPoll.Tick += async (_, _) => await RefreshServerAsync();
        Shown += async (_, _) =>
        {
            _animation.Start();
            ClientPackage.CleanupOldStaging(); ClientPackage.CleanupOldBackups();
            _ = LoadNewsAsync();
            await StartupAsync(repair: false);
            _serverPoll.Start();
        };
    }

    private static int ReadLauncherVersion()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        return version is null ? 0 : version.Major * 100 + version.Minor * 10 + version.Build;
    }

    private float UiScale => DeviceDpi / 96F;

    private void ApplyScale()
    {
        var scale = UiScale;
        ClientSize = new Size((int)Math.Round(LogicalWidth * scale), (int)Math.Round(LogicalHeight * scale));
        _play.Bounds = Rectangle.Round(new RectangleF(94 * scale, 300 * scale, 400 * scale, 62 * scale));
        _play.Font = new Font("Georgia", 32 * scale, FontStyle.Bold | FontStyle.Italic, GraphicsUnit.Pixel);
        _backdrop?.Dispose();
        _backdrop = null;
        Invalidate();
    }

    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        base.OnDpiChanged(e);
        ApplyScale();
    }

    // ---------------------------------------------------------------- flow

    private void Set(string status, string? guardian = null, double? progress = null)
    {
        _status = status;
        if (guardian is not null) _guardianLine = guardian;
        if (progress is not null) _progress = Math.Clamp(progress.Value, 0, 1);
        Invalidate();
    }

    private void SetCheck(int index, CheckState state, string? text = null)
    {
        _checks[index].State = state;
        if (text is not null) _checks[index].Text = text;
        Invalidate();
    }

    private void SetPhase(Phase phase, string button)
    {
        _phase = phase;
        _play.Text = button;
        _play.Enabled = phase is Phase.Ready or Phase.NeedsRepair or Phase.Blocked;
        Invalidate();
    }

    private async Task StartupAsync(bool repair)
    {
        if (_working || IsDisposed) return;
        _working = true;
        try
        {
            SetPhase(Phase.Busy, repair ? "Repairing" : "Checking");
            if (await UpdateAsync(repair)) return; // the update helper takes over and this window closes
            _installedVersion = ClientPackage.ReadInstalledVersion(_root);
            _endpoint = GuardianClient.ReadEndpoint(_root);
            if (!ClientPackage.HasRunnableClient(_root))
            {
                Set("The game files are missing. Check your connection and try again.", "Standing by", 0);
                SetPhase(Phase.NeedsRepair, "Retry");
                return;
            }
            await VerifyFilesAsync();
            await ScanToolsAsync(null);
            await RefreshServerAsync();
            Conclude();
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { }
        finally { _working = false; }
    }

    // Decides what the button does once every check has an answer.
    private void Conclude()
    {
        SetCheck(TokenCheck, CheckState.Waiting, "Issued when you press Play");
        if (_integrity.State == IntegrityState.Modified)
        {
            Set("The client files were changed. Repair to play.", "Action needed", 0);
            SetPhase(Phase.NeedsRepair, "Repair");
        }
        else if (_scan.BotTools.Count > 0)
        {
            Set($"Close {string.Join(", ", _scan.BotTools)} to play.", "Action needed", 0);
            SetPhase(Phase.Blocked, "Check again");
        }
        else
        {
            Set($"Client v{_installedVersion} is up to date", "Ready to protect your session", 1);
            SetPhase(Phase.Ready, "Play");
        }
    }

    // Returns true when an update was handed to the helper process.
    private async Task<bool> UpdateAsync(bool repair)
    {
        Set(repair ? "Downloading the official files again" : "Checking for updates", "Standing by", 0);
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromMinutes(7));
            var release = await ReleaseService.GetManifestAsync(timeout.Token);
            var installed = ClientPackage.ReadInstalledVersion(_root);
            var runnable = ClientPackage.HasRunnableClient(_root);
            if (repair && release.Version < installed)
            {
                Set($"Repair is not available yet for client v{installed}.", null, 0);
                return false;
            }
            if (!repair && release.Version <= installed && runnable) return false;
            if (ClientPackage.IsGameRunningFrom(_root))
            {
                Set($"Update v{release.Version} is ready. Close the game to install it.", null, 0);
                return false;
            }
            Set($"Downloading update v{release.Version}", null, 0);
            _play.Text = "Updating";
            var report = new Progress<double>(value => Set($"Downloading update v{release.Version} · {value * 100:0}%", null, value));
            var package = await ReleaseService.DownloadPackageAsync(release, report, timeout.Token);
            Set("Preparing the files", null, 1);
            var stage = await Task.Run(() =>
            {
                var folder = ClientPackage.ExtractToStaging(package);
                ClientPackage.ValidateStagedPackage(package, folder, release.Version);
                return folder;
            }, timeout.Token);
            var stagedLauncher = Path.Combine(stage, "AntigasLauncher.exe");
            if (!File.Exists(stagedLauncher))
            {
                var currentLauncher = Path.Combine(_root, "AntigasLauncher.exe");
                if (!File.Exists(currentLauncher)) throw new InvalidDataException("The current launcher was not found to finish the installation.");
                File.Copy(currentLauncher, stagedLauncher, false);
            }
            var manifestPath = Path.Combine(Path.GetDirectoryName(package)!, $"release-v{release.Version}.json");
            await File.WriteAllTextAsync(manifestPath, JsonSerializer.Serialize(release), timeout.Token);
            var helper = new ProcessStartInfo(stagedLauncher) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = stage };
            foreach (var argument in new[] { "--apply-update", package, manifestPath, stage, _root, release.Version.ToString(), Environment.ProcessId.ToString() })
                helper.ArgumentList.Add(argument);
            if (repair) helper.ArgumentList.Add("--repair");
            if (Process.Start(helper) is null) throw new InvalidOperationException("The installation could not be started.");
            Application.ExitThread();
            return true;
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { throw; }
        catch (Exception ex)
        {
            LauncherLog.Write(repair ? "repair" : "update-check", ex);
            Set(repair ? "The repair could not be completed." : "Could not check for updates. Using the installed version.", null, 0);
            return false;
        }
    }

    private async Task VerifyFilesAsync()
    {
        SetCheck(FilesCheck, CheckState.Running, "Comparing every file with the official release");
        _guardianLine = "Checking client files";
        var before = _status;
        var report = new Progress<(int Done, int Total)>(value =>
            Set($"Verifying client files · {value.Done} / {value.Total}", null, value.Total == 0 ? 0 : (double)value.Done / value.Total));
        var settings = GuardianClient.ReadClientName(_root) is { } name
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OTClientV8", name) : null;
        try
        {
            _integrity = await Task.Run(() => ClientIntegrity.Verify(_root, _installedVersion, settings, report, _lifetime.Token), _lifetime.Token);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            LauncherLog.Write("verify-files", ex);
            _integrity = new IntegrityResult(IntegrityState.Modified, 0, ["client folder could not be read"]);
        }
        _status = before;
        switch (_integrity.State)
        {
            case IntegrityState.Verified:
                SetCheck(FilesCheck, CheckState.Passed, $"All {_integrity.FileCount} files match the official release");
                break;
            case IntegrityState.NoManifest:
                SetCheck(FilesCheck, CheckState.Waiting, "This install has no signed file list yet");
                break;
            default:
                SetCheck(FilesCheck, CheckState.Failed, "Changed: " + Shorten(string.Join(", ", _integrity.Problems), 70));
                break;
        }
    }

    private async Task ScanToolsAsync(Process? game)
    {
        if (game is null) SetCheck(ToolsCheck, CheckState.Running, "Looking for bots and injectors");
        try { _scan = await Task.Run(() => ProcessScanner.Scan(game, _root), _lifetime.Token); }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            LauncherLog.Write("scan-tools", ex);
            _scan = ScanResult.Clean;
        }
        var found = _scan.BotTools.Concat(_scan.InjectedLibraries).ToArray();
        if (found.Length > 0) SetCheck(ToolsCheck, CheckState.Failed, "Found: " + Shorten(string.Join(", ", found), 60));
        else if (_scan.MacroTools.Count > 0) SetCheck(ToolsCheck, CheckState.Passed, "No bot found. Macro tool open: " + Shorten(string.Join(", ", _scan.MacroTools), 34));
        else SetCheck(ToolsCheck, CheckState.Passed, "No bot or injector found running");
    }

    private async Task RefreshServerAsync()
    {
        if (_endpoint is null || IsDisposed || _lifetime.IsCancellationRequested) return;
        try
        {
            var players = await GuardianClient.GetPlayersOnlineAsync(_endpoint, _lifetime.Token);
            _serverOnline = true;
            if (players is null)
            {
                // An older server answers nothing to the launcher but is reachable.
                SetCheck(ServerCheck, CheckState.Waiting, "This server does not answer the launcher yet");
            }
            else
            {
                _playersOnline = players.Value;
                SetCheck(ServerCheck, CheckState.Passed, "Watches play patterns in game");
            }
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { }
        catch (Exception ex) when (ex is IOException or System.Net.Sockets.SocketException or OperationCanceledException)
        {
            _serverOnline = false;
            SetCheck(ServerCheck, CheckState.Waiting, "The server did not answer");
        }
        Invalidate();
    }

    private async Task LoadNewsAsync()
    {
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromSeconds(20));
            var news = await NewsService.GetAsync(timeout.Token);
            if (news.Count > 0 && !IsDisposed) { _news = news; _newsIndex = 0; Invalidate(); }
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or OperationCanceledException or JsonException or InvalidDataException)
        {
            if (!_lifetime.IsCancellationRequested) LauncherLog.Write("news", ex);
        }
    }

    private async Task OnPrimaryAsync()
    {
        switch (_phase)
        {
            case Phase.NeedsRepair: await StartupAsync(repair: _integrity.State == IntegrityState.Modified); break;
            case Phase.Blocked: await RecheckToolsAsync(); break;
            case Phase.Ready: await PlayAsync(); break;
        }
    }

    private async Task RecheckToolsAsync()
    {
        if (_working) return;
        _working = true;
        try
        {
            SetPhase(Phase.Busy, "Checking");
            await ScanToolsAsync(null);
            Conclude();
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { }
        finally { _working = false; }
    }

    private GuardianFlags CurrentFlags()
    {
        var flags = _integrity.State switch
        {
            IntegrityState.Verified => GuardianFlags.FilesOk,
            IntegrityState.Modified => GuardianFlags.FilesModified,
            _ => GuardianFlags.NoManifest,
        };
        if (_scan.BotTools.Count > 0) flags |= GuardianFlags.BotTool;
        if (_scan.MacroTools.Count > 0) flags |= GuardianFlags.MacroTool;
        if (_scan.InjectedLibraries.Count > 0) flags |= GuardianFlags.Injected;
        return flags;
    }

    private string CurrentDetail() => Shorten(string.Join(", ",
        _scan.BotTools.Concat(_scan.InjectedLibraries).Concat(_scan.MacroTools).Concat(_integrity.Problems)), 280);

    private async Task PlayAsync()
    {
        if (_working) return;
        _working = true;
        try
        {
            SetPhase(Phase.Busy, "Starting");
            if (ClientPackage.IsGameRunningFrom(_root))
            {
                Set("The game is already open. Close it before starting again.", "Standing by");
                SetPhase(Phase.Ready, "Play");
                return;
            }
            await ScanToolsAsync(null);
            if (_scan.BotTools.Count > 0) { Conclude(); return; }

            var sessionFile = Path.Combine(_root, ClientIntegrity.SessionFileName);
            TryDelete(sessionFile);
            GuardianIssue? session = null;
            if (_endpoint is not null)
            {
                Set("Asking the server for a session token", "Signing your session");
                SetCheck(TokenCheck, CheckState.Running, "Asking the server");
                try
                {
                    session = await GuardianClient.IssueAsync(_endpoint, LauncherVersion, _installedVersion, CurrentFlags(), CurrentDetail(), _lifetime.Token);
                    if (session is not null)
                    {
                        await File.WriteAllTextAsync(sessionFile, session.Token, _lifetime.Token);
                        _playersOnline = session.PlayersOnline; _serverOnline = true;
                        _reported = CurrentFlags();
                    }
                }
                catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { throw; }
                catch (Exception ex) when (ex is IOException or System.Net.Sockets.SocketException or OperationCanceledException or UnauthorizedAccessException)
                {
                    LauncherLog.Write("guardian-issue", ex);
                    session = null;
                    TryDelete(sessionFile);
                }
            }
            SetCheck(TokenCheck, session is null ? CheckState.Waiting : CheckState.Passed,
                session is null ? "The server gave no token. Playing without a session" : "Signed for this launch, renewed while you play");

            var exe = Path.Combine(_root, "Antigas_gl.exe");
            Process? game;
            try { game = Process.Start(new ProcessStartInfo(exe) { UseShellExecute = false, WorkingDirectory = _root }); }
            catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or IOException or InvalidOperationException)
            {
                LauncherLog.Write("launch-game", ex);
                game = null;
            }
            if (game is null)
            {
                TryDelete(sessionFile);
                Set("The game could not be started. Check the folder permissions.", "Standing by");
                SetPhase(Phase.Ready, "Play");
                return;
            }
            _game = game;
            Set("Tibia 7.4 is running", session is null ? "Watching this computer" : "Protection active", 1);
            SetPhase(Phase.Running, "Playing");
            WindowState = FormWindowState.Minimized;
            _ = WatchGameAsync(game, session, sessionFile);
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { }
        finally { _working = false; }
    }

    // While the game runs: look again for bot tools every 20 seconds and tell
    // the server at every heartbeat (or at once when something new shows up).
    private async Task WatchGameAsync(Process game, GuardianIssue? session, string sessionFile)
    {
        var token = session?.Token;
        var beatEvery = TimeSpan.FromSeconds(session?.HeartbeatSeconds ?? 60);
        var nextBeat = DateTime.UtcNow + beatEvery;
        try
        {
            while (!game.HasExited)
            {
                try { await game.WaitForExitAsync(_lifetime.Token).WaitAsync(TimeSpan.FromSeconds(20), _lifetime.Token); }
                catch (TimeoutException) { }
                if (game.HasExited) break;
                await ScanToolsAsync(game);
                var flags = CurrentFlags();
                var news = (flags & ~_reported) != 0;
                if (_endpoint is null || (!news && DateTime.UtcNow < nextBeat)) continue;
                nextBeat = DateTime.UtcNow + beatEvery;
                try
                {
                    if (token is not null && !await GuardianClient.HeartbeatAsync(_endpoint, token, flags, CurrentDetail(), _lifetime.Token)) token = null;
                    if (token is null)
                    {
                        // The server restarted or dropped the session: ask again. The client presents the new token at its next login.
                        var renewed = await GuardianClient.IssueAsync(_endpoint, LauncherVersion, _installedVersion, flags, CurrentDetail(), _lifetime.Token);
                        if (renewed is not null)
                        {
                            token = renewed.Token;
                            await File.WriteAllTextAsync(sessionFile, token, _lifetime.Token);
                        }
                    }
                    _reported |= flags;
                    _serverOnline = true;
                    SetCheck(TokenCheck, token is null ? CheckState.Waiting : CheckState.Passed,
                        token is null ? "The server gave no token" : "Signed for this launch, renewed while you play");
                    _guardianLine = token is null ? "Watching this computer" : "Protection active";
                }
                catch (Exception ex) when (ex is IOException or System.Net.Sockets.SocketException or UnauthorizedAccessException ||
                                           (ex is OperationCanceledException && !_lifetime.IsCancellationRequested))
                {
                    SetCheck(TokenCheck, CheckState.Waiting, "The server did not answer the last heartbeat");
                }
            }
        }
        catch (OperationCanceledException) { return; }
        catch (InvalidOperationException) { }
        finally
        {
            TryDelete(sessionFile);
            game.Dispose();
            _game = null;
        }
        if (IsDisposed || _lifetime.IsCancellationRequested) return;
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        await RecheckToolsAsync();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (_phase == Phase.Running && e.CloseReason == CloseReason.UserClosing &&
            MessageBox.Show(this, "The game is still running. Guardian stops watching when the launcher closes, and the server notices.\n\nClose the launcher anyway?",
                "Tibia 7.4 Launcher", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
        {
            e.Cancel = true;
            return;
        }
        base.OnFormClosing(e);
        _lifetime.Cancel();
        _animation.Stop();
        _serverPoll.Stop();
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    private static string Shorten(string text, int max) => text.Length <= max ? text : text[..(max - 1)] + "…";

    private static void Open(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException) { LauncherLog.Write("open-link", ex); }
    }

    // ------------------------------------------------------------- drawing

    private Bitmap Backdrop()
    {
        if (_backdrop is not null) return _backdrop;
        var scale = UiScale;
        var image = new Bitmap(Math.Max(1, ClientSize.Width), Math.Max(1, ClientSize.Height));
        using var g = Graphics.FromImage(image);
        g.ScaleTransform(scale, scale);
        g.InterpolationMode = InterpolationMode.HighQualityBilinear;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;

        using (var wall = WatchtowerArt.MakeWall(SceneWidth, LogicalHeight)) g.DrawImage(wall, 0, 0, SceneWidth, LogicalHeight);
        WatchtowerArt.Vignette(g, new RectangleF(0, 0, SceneWidth, LogicalHeight), new PointF(SceneWidth / 2F, 172));
        WatchtowerArt.Wordmark(g, "Tibia 7.4", SceneWidth / 2F, 114, 70);
        using (var caption = new Font("Georgia", 12, FontStyle.Regular, GraphicsUnit.Pixel))
            WatchtowerArt.Spaced(g, "A CLASSIC RPG VERSION", caption, Color.FromArgb(241, 228, 187), SceneWidth / 2F, 204, 4);
        using (var motto = new Font("Georgia", 15, FontStyle.Italic, GraphicsUnit.Pixel))
        using (var center = new StringFormat { Alignment = StringAlignment.Center })
            WatchtowerArt.ShadowText(g, "A world of adventure, like in the old times.", motto, Color.FromArgb(238, 228, 204),
                new RectangleF(0, 246, SceneWidth, 24), center);

        var side = new RectangleF(SceneWidth, 0, LogicalWidth - SceneWidth, LogicalHeight);
        using (var stone = WatchtowerArt.MakeStone((int)side.Width, LogicalHeight)) g.DrawImage(stone, side.Left, 0, side.Width, side.Height);
        using (var dark = new SolidBrush(Color.FromArgb(21, 25, 18))) g.FillRectangle(dark, side.Left, 0, 1, side.Height);
        using (var light = new SolidBrush(Color.FromArgb(121, 122, 102))) g.FillRectangle(light, side.Left + 1, 0, 1, side.Height);
        using (var title = new Font("Georgia", 26, FontStyle.Bold | FontStyle.Italic, GraphicsUnit.Pixel))
            WatchtowerArt.ShadowText(g, "Guardian", title, WatchtowerArt.GoldStrong, new RectangleF(672, 24, 260, 34), StringFormat.GenericDefault);
        WatchtowerArt.Ridge(g, new RectangleF(608, 92, 332, 2), WatchtowerArt.GoldDeep, Color.FromArgb(60, 50, 26));
        using (var rule = new SolidBrush(Color.FromArgb(106, 109, 95))) g.FillRectangle(rule, 608, 354, 332, 1);
        using (var note = new Font("Georgia", 12, FontStyle.Italic, GraphicsUnit.Pixel))
        using (var noteBrush = new SolidBrush(Color.FromArgb(222, 210, 185)))
            g.DrawString("Fair play keeps the old times alive. Suspected bots are reported to the staff.", note, noteBrush, new RectangleF(608, 363, 332, 36));

        var parchment = new RectangleF(598, 408, 352, 82);
        using (var paper = new LinearGradientBrush(parchment, Color.FromArgb(255, 246, 223), Color.FromArgb(240, 219, 169), LinearGradientMode.Vertical))
            g.FillRectangle(paper, parchment);
        WatchtowerArt.Ridge(g, parchment, Color.FromArgb(236, 214, 150), Color.FromArgb(133, 97, 59));
        _backdrop = image;
        return image;
    }

    protected override void OnPaintBackground(PaintEventArgs e) { }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.DrawImageUnscaled(Backdrop(), 0, 0);
        g.ScaleTransform(UiScale, UiScale);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        _links.Clear();

        // Torches at both sides of the wordmark.
        WatchtowerArt.Torch(g, 84, 112, 3, _frame);
        WatchtowerArt.Torch(g, 477, 112, 3, _frame + 2);

        using var serif13 = new Font("Georgia", 13, FontStyle.Bold, GraphicsUnit.Pixel);
        using var sans11 = new Font("Verdana", 11, FontStyle.Regular, GraphicsUnit.Pixel);
        using var sans10 = new Font("Verdana", 10.5F, FontStyle.Regular, GraphicsUnit.Pixel);
        using var near = new StringFormat { FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter };
        using var center = new StringFormat { Alignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter };

        // Server line and links.
        var dot = _serverOnline switch { true => WatchtowerArt.Ok, false => WatchtowerArt.Bad, _ => WatchtowerArt.Idle };
        using (var dotBrush = new SolidBrush(dot)) g.FillEllipse(dotBrush, 16, 17, 9, 9);
        var server = _serverOnline switch
        {
            true when _checks[ServerCheck].State == CheckState.Passed => $"Server online · {_playersOnline} {(_playersOnline == 1 ? "player" : "players")}",
            true => "Server online",
            false => "Server offline",
            _ => "Looking for the server",
        };
        WatchtowerArt.ShadowText(g, server, serif13, WatchtowerArt.Light, new RectangleF(32, 13, 330, 20), near);
        Link(g, "Website", serif13, WatchtowerArt.Light, 448, 13, () => Open(WebsiteUrl));
        Link(g, "Discord", serif13, WatchtowerArt.Light, 518, 13, () => Open(DiscordUrl));

        // Progress and status under the Play button.
        var bar = new RectangleF(94, 372, 400, 16);
        using (var track = new SolidBrush(WatchtowerArt.StoneDeep)) g.FillRectangle(track, bar);
        var inner = RectangleF.Inflate(bar, -2, -2);
        var filled = (float)(inner.Width * _progress);
        if (filled >= 1)
        {
            var state = g.Save();
            g.SetClip(new RectangleF(inner.Left, inner.Top, filled, inner.Height));
            using var gold = new SolidBrush(WatchtowerArt.GoldStrong);
            using var notch = new SolidBrush(Color.FromArgb(179, 141, 44));
            using var shine = new SolidBrush(Color.FromArgb(120, 255, 240, 166));
            using var shade = new SolidBrush(Color.FromArgb(130, 125, 93, 22));
            g.FillRectangle(gold, inner);
            for (var x = inner.Left + 10; x < inner.Right; x += 12) g.FillRectangle(notch, x, inner.Top, 2, inner.Height);
            g.FillRectangle(shine, inner.Left, inner.Top, inner.Width, 2);
            g.FillRectangle(shade, inner.Left, inner.Bottom - 3, inner.Width, 3);
            g.Restore(state);
        }
        WatchtowerArt.Ridge(g, bar, WatchtowerArt.StoneEdge, Color.FromArgb(21, 25, 18));
        using (var statusBrush = new SolidBrush(Color.FromArgb(222, 210, 185)))
            g.DrawString(_status, sans11, statusBrush, new RectangleF(40, 396, SceneWidth - 80, 18), center);
        using (var versionBrush = new SolidBrush(Color.FromArgb(169, 162, 140)))
            g.DrawString(_installedVersion > 0 ? $"Client v{_installedVersion} · OpenGL" : "OpenGL", sans10, versionBrush, new RectangleF(16, 476, 300, 16), near);

        // Guardian.
        var active = _phase is Phase.Ready or Phase.Running || (_phase == Phase.Busy && _play.Text == "Starting");
        var shield = new RectangleF(608, 20, 50, 59);
        if (_phase == Phase.Running)
        {
            using var halo = new GraphicsPath();
            halo.AddEllipse(RectangleF.Inflate(shield, 14, 10));
            using var glow = new PathGradientBrush(halo) { CenterColor = Color.FromArgb(90 + 20 * (_frame % 2), 231, 197, 70), SurroundColors = [Color.FromArgb(0, 231, 197, 70)] };
            g.FillPath(glow, halo);
        }
        WatchtowerArt.Shield(g, shield, active);
        using (var lineBrush = new SolidBrush(Color.FromArgb(222, 210, 185)))
            g.DrawString(_guardianLine, sans11, lineBrush, new RectangleF(673, 60, 270, 16), near);

        using var checkTitle = new Font("Georgia", 14, FontStyle.Bold, GraphicsUnit.Pixel);
        for (var i = 0; i < _checks.Length; i++)
        {
            var check = _checks[i];
            var top = 108 + i * 60;
            var box = new RectangleF(608, top + 1, 17, 17);
            var pulse = check.State == CheckState.Running && _frame % 4 < 2;
            using (var fill = new SolidBrush(pulse ? WatchtowerArt.Busy : WatchtowerArt.StoneDeep)) g.FillRectangle(fill, box);
            var edge = check.State switch
            {
                CheckState.Passed => WatchtowerArt.Ok, CheckState.Failed => WatchtowerArt.Bad,
                CheckState.Running => WatchtowerArt.Busy, _ => WatchtowerArt.Idle,
            };
            using (var pen = new Pen(edge, 1)) g.DrawRectangle(pen, box.Left + .5F, box.Top + .5F, box.Width - 1, box.Height - 1);
            if (check.State == CheckState.Passed)
            {
                using var mark = new Pen(WatchtowerArt.Ok, 2.2F);
                g.DrawLines(mark, [new PointF(box.Left + 4, box.Top + 9), new PointF(box.Left + 7.5F, box.Top + 12.5F), new PointF(box.Left + 13, box.Top + 5)]);
            }
            else if (check.State == CheckState.Failed)
            {
                using var mark = new Pen(WatchtowerArt.Bad, 2.2F);
                g.DrawLine(mark, box.Left + 4.5F, box.Top + 4.5F, box.Right - 4.5F, box.Bottom - 4.5F);
                g.DrawLine(mark, box.Right - 4.5F, box.Top + 4.5F, box.Left + 4.5F, box.Bottom - 4.5F);
            }
            WatchtowerArt.ShadowText(g, check.Title, checkTitle, Color.FromArgb(247, 242, 230), new RectangleF(636, top - 1, 300, 20), near);
            using var textBrush = new SolidBrush(check.State == CheckState.Failed ? Color.FromArgb(255, 190, 178) : WatchtowerArt.Dim);
            g.DrawString(check.Text, sans11, textBrush, new RectangleF(637, top + 20, 303, 32));
        }

        // News.
        var item = _news[Math.Clamp(_newsIndex, 0, _news.Count - 1)];
        using (var date = new Font("Georgia", 11, FontStyle.Italic, GraphicsUnit.Pixel))
        using (var wine = new SolidBrush(WatchtowerArt.Wine))
            g.DrawString(item.Date, date, wine, new RectangleF(608, 415, 250, 14), near);
        using (var headline = new Font("Georgia", 13, FontStyle.Bold, GraphicsUnit.Pixel))
        using (var ink = new SolidBrush(WatchtowerArt.Ink))
        using (var wrap = new StringFormat { Trimming = StringTrimming.EllipsisWord })
            g.DrawString(item.Title, headline, ink, new RectangleF(608, 430, 276, 34), wrap);
        using (var readMore = new Font("Verdana", 10.5F, FontStyle.Bold | FontStyle.Underline, GraphicsUnit.Pixel))
            Link(g, "Read on the website", readMore, WatchtowerArt.Wine, 608, 468, () => Open(WebsiteUrl), shadow: false);
        if (_news.Count > 1)
        {
            Arrow(g, new RectangleF(890, 416, 24, 24), "‹", () => { _newsIndex = (_newsIndex + _news.Count - 1) % _news.Count; Invalidate(); });
            Arrow(g, new RectangleF(918, 416, 24, 24), "›", () => { _newsIndex = (_newsIndex + 1) % _news.Count; Invalidate(); });
        }
    }

    private void Link(Graphics g, string text, Font font, Color color, float x, float y, Action action, bool shadow = true)
    {
        var size = g.MeasureString(text, font);
        var area = new RectangleF(x, y, size.Width, size.Height);
        if (shadow) WatchtowerArt.ShadowText(g, text, font, color, area, StringFormat.GenericDefault);
        else { using var brush = new SolidBrush(color); g.DrawString(text, font, brush, area.Location); }
        _links.Add((area, action));
    }

    private void Arrow(Graphics g, RectangleF area, string glyph, Action action)
    {
        using (var fill = new SolidBrush(Color.FromArgb(236, 212, 154))) g.FillRectangle(fill, area);
        using (var pen = new Pen(WatchtowerArt.ParchmentEdge)) g.DrawRectangle(pen, area.Left + .5F, area.Top + .5F, area.Width - 1, area.Height - 1);
        using var font = new Font("Georgia", 17, FontStyle.Bold, GraphicsUnit.Pixel);
        using var ink = new SolidBrush(WatchtowerArt.Ink);
        using var center = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        g.DrawString(glyph, font, ink, new RectangleF(area.Left, area.Top - 2, area.Width, area.Height), center);
        _links.Add((area, action));
    }

    private Action? LinkAt(Point location)
    {
        var point = new PointF(location.X / UiScale, location.Y / UiScale);
        foreach (var (area, action) in _links)
            if (area.Contains(point)) return action;
        return null;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        Cursor = LinkAt(e.Location) is null ? Cursors.Default : Cursors.Hand;
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        if (e.Button == MouseButtons.Left) LinkAt(e.Location)?.Invoke();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _animation.Dispose();
            _serverPoll.Dispose();
            _backdrop?.Dispose();
        }
        base.Dispose(disposing);
    }
}
