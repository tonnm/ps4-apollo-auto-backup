using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Apollo.Core;

// Lifetime containment: a crashed GUI must not leave its monitor running behind it.
public sealed class HiddenProcess : IDisposable
{
    private readonly SafeFileHandle job;
    public Process Process { get; }
    private readonly Task outputDrain;
    private readonly Task errorDrain;
    private readonly Queue<string> output = new();
    public string Details { get { lock (output) return string.Join(Environment.NewLine, output); } }
    public bool Running => !Process.HasExited;

    public static ProcessStartInfo PowerShell(string script, params string[] arguments)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"))
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            WorkingDirectory = Path.GetDirectoryName(Path.GetFullPath(script))!
        };
        foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.GetFullPath(script) }.Concat(arguments)) start.ArgumentList.Add(arg);
        return start;
    }

    public HiddenProcess(ProcessStartInfo start)
    {
        job = CreateJobObject(IntPtr.Zero, null);
        if (job.IsInvalid) throw new Win32Exception();
        var limits = new ExtendedLimits { Basic = new BasicLimits { LimitFlags = 0x2000 } }; // KILL_ON_JOB_CLOSE
        if (!SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf<ExtendedLimits>())) { job.Dispose(); throw new Win32Exception(); }
        Process = new Process { StartInfo = start };
        try
        {
            Process.Start();
            if (!AssignProcessToJobObject(job, Process.Handle)) throw new Win32Exception();
            outputDrain = Drain(Process.StandardOutput);
            errorDrain = Drain(Process.StandardError);
        }
        catch
        {
            try { if (!Process.HasExited) Process.Kill(true); } catch (InvalidOperationException) { }
            Process.Dispose(); job.Dispose(); throw;
        }
    }

    private async Task Drain(StreamReader reader)
    {
        while (await reader.ReadLineAsync() is { } line)
            lock (output) { output.Enqueue(line.Length > 512 ? line[..512] : line); while (output.Count > 20) output.Dequeue(); }
    }
    public async Task<int> WaitAsync()
    {
        await Process.WaitForExitAsync();
        await Task.WhenAll(outputDrain, errorDrain);
        return Process.ExitCode;
    }
    public void Dispose()
    {
        job.Dispose(); // The OS terminates only processes assigned to this job.
        try { Process.WaitForExit(3000); } catch (InvalidOperationException) { }
        Process.Dispose();
    }

    [StructLayout(LayoutKind.Sequential)] private struct BasicLimits
    {
        public long ProcessTime, JobTime; public uint LimitFlags; public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] private struct IoCounters { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
    [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimits
    {
        public BasicLimits Basic; public IoCounters Io; public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern SafeFileHandle CreateJobObject(IntPtr attributes, string? name);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetInformationJobObject(SafeFileHandle job, int infoClass, ref ExtendedLimits limits, uint size);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
}
