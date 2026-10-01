using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Apollo.Core;

public sealed record BackupResult(DateTime Completed, int New, int Changed, int Unchanged, int Failures)
{
    public int Total => checked(New + Changed + Unchanged + Failures);
    public string Title => Failures > 0 ? "Backup completed with failures" : "Backup completed";
    public string Summary => $"{Total} saves checked · {New} new · {Changed} changed · {Unchanged} unchanged · {Failures} failures";
    public string Activity => $"{Completed:g}   {Title} — {New} new, {Changed} changed, {Failures} failures";
}

public sealed record FailedAttempt(DateTime Completed, int? ExitCode);

public static partial class History
{
    [GeneratedRegex(@"^\[(?<date>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[INFO\] (?:Backup finished with exit code (?<code>-?\d+)\.|Backup execution failed: [^\r\n]+)\r?$", RegexOptions.Multiline)]
    private static partial Regex FailurePattern();

    public static IReadOnlyList<FailedAttempt> ParseFailures(string monitorLog)
    {
        var failures = new List<FailedAttempt>();
        foreach (Match match in FailurePattern().Matches(monitorLog))
        {
            if (!DateTime.TryParseExact(match.Groups["date"].Value, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)) continue;
            int? code = null;
            if (match.Groups["code"].Success)
            {
                if (!int.TryParse(match.Groups["code"].Value, out var parsed) || parsed == 0) continue;
                code = parsed;
            }
            failures.Add(new(date, code));
        }
        return failures.TakeLast(10).Reverse().ToArray();
    }

    // This is the v1.0.0 engine's persisted summary, not its decorative console output.
    [GeneratedRegex(@"^\[(?<date>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[INFO\] Backup complete\. New=(?<n>\d+) Changed=(?<c>\d+) Unchanged=(?<u>\d+) Failures=(?<f>\d+)\r?$", RegexOptions.Multiline)]
    private static partial Regex SummaryPattern();

    public static IReadOnlyList<BackupResult> Parse(string text)
    {
        var results = new List<BackupResult>();
        foreach (Match match in SummaryPattern().Matches(text))
        {
            if (!DateTime.TryParseExact(match.Groups["date"].Value, "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)) continue;
            if (!int.TryParse(match.Groups["n"].Value, out var n) || !int.TryParse(match.Groups["c"].Value, out var c) ||
                !int.TryParse(match.Groups["u"].Value, out var u) || !int.TryParse(match.Groups["f"].Value, out var f)) continue;
            if ((long)n + c + u + f > int.MaxValue) continue;
            results.Add(new(date, n, c, u, f));
        }
        return results.TakeLast(10).Reverse().ToArray();
    }

    public static string ReadTail(string file, int maxBytes = 128 * 1024)
    {
        if (!File.Exists(file)) return "";
        using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        var offset = Math.Max(0, stream.Length - maxBytes);
        stream.Seek(offset, SeekOrigin.Begin);
        using var reader = new StreamReader(stream, Encoding.UTF8, true);
        if (offset > 0) reader.ReadLine(); // Ignore a truncated first line/UTF-8 sequence.
        return reader.ReadToEnd();
    }

    public static string ExitMessage(int code) => code switch
    {
        0 => "Backup completed",
        10 => "PS4/Apollo unreachable. Turn on the console and enable Apollo's web server, then try again.",
        11 => "Apollo did not list any saves. Check its web server and exposed saves.",
        12 => "Another backup is already running. Wait for it to finish.",
        13 => "The backup history file needs attention. Your existing backups were preserved. Open Diagnostics for details.",
        20 => "Backup completed with failures. Some saves could not be downloaded or processed. Open the backup log for details.",
        _ => "The backup could not finish. Check folder permissions, free space and the backup log."
    };
}
