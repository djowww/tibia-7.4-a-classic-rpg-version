// Tibia74-Local.exe: sobe o servidor local (Docker) e abre o cliente.
// Compilar com local/launcher/build.ps1 (usa o csc do .NET Framework do Windows).
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

[assembly: AssemblyTitle("Tibia 7.4 Local")]
[assembly: AssemblyProduct("Tibia 7.4 Local")]
[assembly: AssemblyDescription("Inicia o servidor local e abre o cliente")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class Program
{
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);

    const int Minimize = 6;
    const int Restore = 9;

    static int Main()
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }
        Console.Title = "Tibia 7.4 Local";
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, Path.Combine("local", "start.ps1"));
        string clientDir = Path.Combine(root, Path.Combine("local", "client"));
        string client = Path.Combine(clientDir, "Antigas_gl.exe");

        Say(ConsoleColor.Yellow, "Tibia 7.4 Local");
        if (!File.Exists(script) || !File.Exists(Path.Combine(root, "compose.yaml")))
            return Fail("Arquivos do pacote não encontrados. Extraia o zip inteiro e abra o Tibia74-Local.exe de dentro da pasta extraída.");

        Say(ConsoleColor.Gray, "Preparando o servidor local. Na primeira vez isso leva alguns minutos e precisa de internet.");
        int code = Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -NoLaunch", root);
        if (code != 0) return Fail("O servidor local não iniciou. Veja a mensagem acima.");
        if (!File.Exists(client)) return Fail("Cliente não encontrado em local\\client.");

        Say(ConsoleColor.Green, "Abrindo o jogo. Ao fechar o jogo o servidor é parado e o progresso fica salvo.");
        Process game;
        try
        {
            ProcessStartInfo info = new ProcessStartInfo(client);
            info.WorkingDirectory = clientDir;
            info.UseShellExecute = false;
            game = Process.Start(info);
        }
        catch (Exception error) { return Fail("Não foi possível abrir o cliente: " + error.Message); }

        IntPtr console = GetConsoleWindow();
        if (console != IntPtr.Zero) ShowWindow(console, Minimize);
        game.WaitForExit();
        if (console != IntPtr.Zero) ShowWindow(console, Restore);

        Say(ConsoleColor.Gray, "Jogo fechado. Parando o servidor local...");
        Run("docker", "compose stop", root);
        Say(ConsoleColor.Green, "Pronto, servidor parado. Pode fechar esta janela.");
        System.Threading.Thread.Sleep(2500);
        return 0;
    }

    static int Run(string file, string arguments, string directory)
    {
        try
        {
            ProcessStartInfo info = new ProcessStartInfo(file, arguments);
            info.WorkingDirectory = directory;
            info.UseShellExecute = false;
            using (Process process = Process.Start(info))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            Say(ConsoleColor.Red, file + ": " + error.Message);
            return -1;
        }
    }

    static void Say(ConsoleColor color, string text)
    {
        ConsoleColor previous = Console.ForegroundColor;
        Console.ForegroundColor = color;
        Console.WriteLine(text);
        Console.ForegroundColor = previous;
    }

    static int Fail(string text)
    {
        Say(ConsoleColor.Red, text);
        Console.WriteLine("Pressione Enter para fechar.");
        try { Console.ReadLine(); } catch { }
        return 1;
    }
}
