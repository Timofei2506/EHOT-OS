using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace EhotUsbCreator;

public static class RawIsoWriter
{
    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_NO_BUFFERING = 0x20000000;
    private const uint FILE_FLAG_WRITE_THROUGH = 0x80000000;
    private const uint FSCTL_LOCK_VOLUME = 0x00090018;
    private const uint FSCTL_DISMOUNT_VOLUME = 0x00090020;
    private const int CHUNK_SIZE = 1024 * 1024; // 1 MiB sector-aligned

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFileW(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(
        SafeFileHandle hDevice,
        uint dwIoControlCode,
        IntPtr lpInBuffer,
        uint nInBufferSize,
        IntPtr lpOutBuffer,
        uint nOutBufferSize,
        out uint lpBytesReturned,
        IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FlushFileBuffers(SafeFileHandle hFile);

    /// <summary>
    /// Resolves either a standalone .iso file OR sequential split parts (.iso.part.aa, .ab, ... or .part.00, .01, ...).
    /// </summary>
    public static List<string> ResolveInputFiles(string selectedPath)
    {
        if (!File.Exists(selectedPath))
            throw new FileNotFoundException("Выбранный файл образа не найден.", selectedPath);

        var match = Regex.Match(selectedPath, @"^(.*\.iso)\.part\.([A-Za-z0-9]+)$", RegexOptions.IgnoreCase);
        if (!match.Success)
            return new List<string> { selectedPath };

        var baseIso = match.Groups[1].Value;
        var dir = Path.GetDirectoryName(selectedPath) ?? ".";
        var prefix = Path.GetFileName(baseIso) + ".part.";

        var parts = Directory.GetFiles(dir, prefix + "*")
            .Where(f => !f.EndsWith(".sha256", StringComparison.OrdinalIgnoreCase))
            .OrderBy(f => f, StringComparer.Ordinal)
            .ToList();

        if (parts.Count == 0)
            throw new FileNotFoundException("Не найдены части многотомного ISO.", selectedPath);
        return parts;
    }

    public static string ComputeStreamSha256(
        IReadOnlyList<string> inputFiles,
        Action<double>? onProgress,
        CancellationToken ct)
    {
        long totalBytes = inputFiles.Sum(f => new FileInfo(f).Length);
        long processed = 0;
        var buffer = new byte[CHUNK_SIZE];
        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);

        foreach (var file in inputFiles)
        {
            using var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, CHUNK_SIZE);
            int read;
            while ((read = fs.Read(buffer, 0, buffer.Length)) > 0)
            {
                ct.ThrowIfCancellationRequested();
                sha.AppendData(buffer, 0, read);
                processed += read;
                if (totalBytes > 0)
                    onProgress?.Invoke((double)processed / totalBytes);
            }
        }
        return Convert.ToHexString(sha.GetHashAndReset()).ToLowerInvariant();
    }

    public static string? TryFindExpectedSha256(IReadOnlyList<string> inputFiles)
    {
        var first = inputFiles[0];
        var baseIso = Regex.Replace(first, @"\.part\.[A-Za-z0-9]+$", "", RegexOptions.IgnoreCase);
        var candidates = new[] { baseIso + ".sha256", first + ".sha256" };
        foreach (var c in candidates)
        {
            if (!File.Exists(c))
                continue;
            var text = File.ReadAllText(c);
            var m = Regex.Match(text, @"\b([a-fA-F0-9]{64})\b");
            if (m.Success)
                return m.Groups[1].Value.ToLowerInvariant();
        }
        return null;
    }

    public static void WriteIsoToUsbDisk(
        UsbDiskInfo disk,
        IReadOnlyList<string> inputFiles,
        Action<string> log,
        Action<double, string> onProgress,
        CancellationToken ct)
    {
        long totalBytes = inputFiles.Sum(f => new FileInfo(f).Length);
        if ((ulong)totalBytes > disk.SizeBytes)
            throw new InvalidOperationException("Размер образа превышает объём выбранной USB-флешки!");

        // 1. Lock and dismount all mounted logical volumes on the target USB stick
        var volumeHandles = new List<SafeFileHandle>();
        try
        {
            foreach (var letter in disk.DriveLetters)
            {
                var clean = letter.TrimEnd('\\');
                var volPath = $@"\\.\{clean}";
                log($"Блокировка и размонтирование тома {clean}...");
                var hVol = CreateFileW(volPath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
                if (!hVol.IsInvalid)
                {
                    volumeHandles.Add(hVol);
                    DeviceIoControl(hVol, FSCTL_LOCK_VOLUME, IntPtr.Zero, 0, IntPtr.Zero, 0, out _, IntPtr.Zero);
                    DeviceIoControl(hVol, FSCTL_DISMOUNT_VOLUME, IntPtr.Zero, 0, IntPtr.Zero, 0, out _, IntPtr.Zero);
                }
            }

            // 2. Clean old partition table safely via diskpart for this specific USB Disk Index
            log($"Очистка старой таблицы разделов на диске #{disk.DiskIndex} ({disk.Model})...");
            RunDiskpartClean(disk.DiskIndex);
            Thread.Sleep(800);

            // 3. Open physical USB device for aligned raw write
            log($"Открытие {disk.DeviceId} для прямой записи...");
            using var hDisk = CreateFileW(
                disk.DeviceId,
                GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_WRITE_THROUGH | FILE_FLAG_NO_BUFFERING,
                IntPtr.Zero);

            if (hDisk.IsInvalid)
                throw new Win32Exception(Marshal.GetLastWin32Error(), $"Не удалось открыть {disk.DeviceId} для записи.");

            var buffer = new byte[CHUNK_SIZE];
            long writtenTotal = 0;
            var sw = Stopwatch.StartNew();
            byte[]? expectedFirst8MbHash = null;
            using var headVerifySha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            long headBytesLimit = Math.Min(8L * 1024 * 1024, totalBytes);
            long headHashed = 0;

            using (var rawOut = new FileStream(hDisk, FileAccess.Write, CHUNK_SIZE, false))
            {
                foreach (var file in inputFiles)
                {
                    ct.ThrowIfCancellationRequested();
                    log($"Запись файла: {Path.GetFileName(file)}");
                    using var src = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, CHUNK_SIZE);
                    int read;
                    while ((read = src.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        ct.ThrowIfCancellationRequested();

                        if (headHashed < headBytesLimit)
                        {
                            int take = (int)Math.Min(read, headBytesLimit - headHashed);
                            headVerifySha.AppendData(buffer, 0, take);
                            headHashed += take;
                        }

                        // Sector-align final tail chunk to 4096 bytes if ISO size isn't exact multiple of 4096
                        int writeLen = read;
                        if (writeLen % 4096 != 0)
                        {
                            int padded = ((writeLen + 4095) / 4096) * 4096;
                            Array.Clear(buffer, writeLen, padded - writeLen);
                            writeLen = padded;
                        }

                        rawOut.Write(buffer, 0, writeLen);
                        writtenTotal += read;

                        double ratio = totalBytes > 0 ? (double)writtenTotal / totalBytes : 0;
                        double mbPerSec = sw.Elapsed.TotalSeconds > 0.2
                            ? (writtenTotal / 1_048_576.0) / sw.Elapsed.TotalSeconds
                            : 0;
                        onProgress(ratio, $"{writtenTotal / 1_048_576} / {totalBytes / 1_048_576} МиБ ({mbPerSec:F1} МиБ/с)");
                    }
                }
                rawOut.Flush();
            }

            FlushFileBuffers(hDisk);
            expectedFirst8MbHash = headVerifySha.GetHashAndReset();

            // 4. Verify initial 8 MiB (MBR/GPT + bootloader + ISO header) readback from USB
            log("Контрольная проверка записанных загрузочных секторов (первые 8 МиБ)...");
            using var hRead = CreateFileW(
                disk.DeviceId,
                GENERIC_READ,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_NO_BUFFERING,
                IntPtr.Zero);

            if (!hRead.IsInvalid)
            {
                using var rawIn = new FileStream(hRead, FileAccess.Read, CHUNK_SIZE, false);
                using var readSha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                long remaining = headBytesLimit;
                while (remaining > 0)
                {
                    int toRead = (int)Math.Min(buffer.Length, remaining);
                    int r = rawIn.Read(buffer, 0, toRead);
                    if (r <= 0) break;
                    readSha.AppendData(buffer, 0, r);
                    remaining -= r;
                }
                var actualHash = readSha.GetHashAndReset();
                if (!actualHash.SequenceEqual(expectedFirst8MbHash))
                    throw new IOException("Ошибка верификации: прочитанные сектора не совпадают с образом!");
                log("Контрольная проверка загрузочной области пройдена на 100%.");
            }
        }
        finally
        {
            foreach (var h in volumeHandles)
                h.Dispose();
        }
    }

    private static void RunDiskpartClean(int diskIndex)
    {
        var scriptPath = Path.GetTempFileName();
        try
        {
            File.WriteAllText(scriptPath, $"select disk {diskIndex}\nclean\nrescan\n");
            var psi = new ProcessStartInfo("diskpart.exe", $"/s \"{scriptPath}\"")
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using var proc = Process.Start(psi) ?? throw new InvalidOperationException("Не удалось запустить diskpart.exe");
            var stdout = proc.StandardOutput.ReadToEnd();
            var stderr = proc.StandardError.ReadToEnd();
            proc.WaitForExit(30000);
            if (proc.ExitCode != 0)
                throw new InvalidOperationException($"diskpart clean завершился с кодом {proc.ExitCode}: {stdout} {stderr}");
        }
        finally
        {
            try { File.Delete(scriptPath); } catch { /* ignore */ }
        }
    }
}
