using System;
using System.Collections.Generic;
using System.Management;

namespace EhotUsbCreator;

public sealed class UsbDiskInfo
{
    public int DiskIndex { get; init; }
    public string DeviceId { get; init; } = string.Empty; // e.g. \\.\PHYSICALDRIVE2
    public string Model { get; init; } = string.Empty;
    public string SerialNumber { get; init; } = string.Empty;
    public ulong SizeBytes { get; init; }
    public List<string> DriveLetters { get; init; } = new();

    public double SizeGb => Math.Round(SizeBytes / 1_000_000_000.0, 1);

    public bool IsLikelyKingstonTarget =>
        Model.Contains("Kingston", StringComparison.OrdinalIgnoreCase) ||
        Model.Contains("DataTraveler", StringComparison.OrdinalIgnoreCase);

    public string DisplayLabel
    {
        get
        {
            var letters = DriveLetters.Count > 0 ? string.Join(", ", DriveLetters) : "без буквы";
            var badge = IsLikelyKingstonTarget ? " [★ Kingston]" : "";
            return $"Диск #{DiskIndex}: {Model} — {SizeGb:F1} ГБ ({letters}){badge}";
        }
    }
}

public static class UsbDiskService
{
    public static List<UsbDiskInfo> ListUsbDisks()
    {
        var result = new List<UsbDiskInfo>();

        // Strictly query ONLY USB physical disk drives — internal SATA/NVMe system drives are excluded.
        using var searcher = new ManagementObjectSearcher(
            "SELECT Index, DeviceID, Model, InterfaceType, MediaType, Size, SerialNumber FROM Win32_DiskDrive WHERE InterfaceType='USB'");

        foreach (ManagementObject drive in searcher.Get())
        {
            var interfaceType = drive["InterfaceType"]?.ToString() ?? string.Empty;
            var mediaType = drive["MediaType"]?.ToString() ?? string.Empty;
            if (!string.Equals(interfaceType, "USB", StringComparison.OrdinalIgnoreCase))
                continue;
            if (mediaType.Contains("Fixed", StringComparison.OrdinalIgnoreCase) &&
                !mediaType.Contains("External", StringComparison.OrdinalIgnoreCase) &&
                !mediaType.Contains("Removable", StringComparison.OrdinalIgnoreCase))
            {
                // Allow external USB drives, still require explicit Size > 4 GB
            }

            var index = Convert.ToInt32(drive["Index"]);
            var deviceId = drive["DeviceID"]?.ToString() ?? $@"\\.\PHYSICALDRIVE{index}";
            var model = (drive["Model"]?.ToString() ?? "USB Flash Drive").Trim();
            var serial = (drive["SerialNumber"]?.ToString() ?? string.Empty).Trim();
            var sizeBytes = drive["Size"] != null ? Convert.ToUInt64(drive["Size"]) : 0UL;

            if (sizeBytes < 4_000_000_000UL)
                continue;

            var letters = GetDriveLettersForDisk(deviceId);
            result.Add(new UsbDiskInfo
            {
                DiskIndex = index,
                DeviceId = deviceId,
                Model = model,
                SerialNumber = serial,
                SizeBytes = sizeBytes,
                DriveLetters = letters
            });
        }

        return result;
    }

    private static List<string> GetDriveLettersForDisk(string deviceId)
    {
        var letters = new List<string>();
        var escaped = deviceId.Replace(@"\", @"\\");
        try
        {
            using var partSearcher = new ManagementObjectSearcher(
                $"ASSOCIATORS OF {{Win32_DiskDrive.DeviceID='{escaped}'}} WHERE AssocClass=Win32_DiskDriveToDiskPartition");
            foreach (ManagementObject partition in partSearcher.Get())
            {
                var partId = partition["DeviceID"]?.ToString();
                if (string.IsNullOrEmpty(partId))
                    continue;
                using var logicalSearcher = new ManagementObjectSearcher(
                    $"ASSOCIATORS OF {{Win32_DiskPartition.DeviceID='{partId}'}} WHERE AssocClass=Win32_LogicalDiskToPartition");
                foreach (ManagementObject logical in logicalSearcher.Get())
                {
                    var name = logical["DeviceID"]?.ToString();
                    if (!string.IsNullOrEmpty(name))
                        letters.Add(name);
                }
            }
        }
        catch
        {
            // Ignore WMI partition lookup errors on unformatted sticks
        }
        return letters;
    }
}
