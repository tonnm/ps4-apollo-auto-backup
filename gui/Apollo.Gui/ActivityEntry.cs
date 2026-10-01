using System.Collections.Generic;
using System;
using System.Linq;
using Apollo.Core;

namespace Apollo.Gui;

// Presentation only: counts come from summaries; unsuccessful attempts come from monitor outcomes.
public sealed record ActivityEntry(BackupResult? Result, FailedAttempt? Failure = null)
{
    public DateTime Completed => Failure?.Completed ?? Result!.Completed;
    public string Time => Completed.ToString("HH:mm");
    public string Timestamp => Completed.ToString("g");
    public string Label => Failure != null ? "Automatic backup failed" : Result!.Failures > 0 ? "Failures" :
        Result.New > 0 && Result.Changed > 0 ? "New + changed saves" :
        Result.New > 0 ? "New saves" : Result.Changed > 0 ? "Changed saves" : "No changes";
    public string Foreground => Failure != null || Result!.Failures > 0 ? "#9C2929" : Result.New > 0 ? "#17613E" : Result.Changed > 0 ? "#235595" : "#526175";
    public string Background => Failure != null || Result!.Failures > 0 ? "#FCEDED" : Result.New > 0 ? "#EAF5EF" : Result.Changed > 0 ? "#EAF1FA" : "#EEF1F5";
    public string Detail
    {
        get
        {
            if (Failure != null) return "Check could not finish successfully. See Diagnostics.";
            var Result = this.Result!;
            var parts = new List<string>();
            if (Result.New > 0) parts.Add($"{Result.New} new");
            if (Result.Changed > 0) parts.Add($"{Result.Changed} changed");
            if (Result.Unchanged > 0) parts.Add($"{Result.Unchanged} unchanged");
            if (Result.Failures > 0) parts.Add($"{Result.Failures} failed");
            return parts.Count > 0 ? string.Join(" · ", parts) : "No saves changed";
        }
    }
    public static IReadOnlyList<ActivityEntry> Merge(IReadOnlyList<BackupResult> results, IReadOnlyList<FailedAttempt> failures) =>
        results.Select(r => new ActivityEntry(r)).Concat(failures.Select(f => new ActivityEntry(null, f)))
            .OrderByDescending(e => e.Completed).Take(10).ToArray();
    public static string Outcome(BackupResult? result) => result == null ? "No completed backup yet" :
        result.Failures > 0 ? "Backup completed with failures" : "Backup completed successfully";
}
