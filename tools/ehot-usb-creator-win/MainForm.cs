using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace EhotUsbCreator;

public sealed class MainForm : Form
{
    private readonly TextBox _isoPathBox = new() { ReadOnly = true };
    private readonly TextBox _expectedShaBox = new();
    private readonly ComboBox _usbCombo = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly CheckBox _verifyShaCheck = new() { Checked = true, Text = "Проверить SHA-256 перед записью" };
    private readonly CheckBox _confirmWipeCheck = new() { Text = "Я подтверждаю полное удаление всех данных на выбранной USB-флешке" };
    private readonly Button _browseBtn = new() { Text = "Выбрать ISO..." };
    private readonly Button _refreshBtn = new() { Text = "Обновить USB" };
    private readonly Button _writeBtn = new() { Text = "Записать EHOT OS на флешку" };
    private readonly ProgressBar _progress = new() { Minimum = 0, Maximum = 1000 };
    private readonly Label _statusLabel = new() { Text = "Готов к работе. Выберите образ EHOT OS и USB-флешку." };
    private readonly TextBox _logBox = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical };

    private List<UsbDiskInfo> _disks = new();
    private List<string> _resolvedFiles = new();
    private CancellationTokenSource? _cts;

    public MainForm()
    {
        Text = "EHOT OS USB Creator — Запись Kingston DataTraveler";
        ClientSize = new Size(760, 560);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;

        // Black & Violet EHOT OS theme
        var bg = Color.FromArgb(11, 9, 20);
        var panelBg = Color.FromArgb(20, 16, 38);
        var accent = Color.FromArgb(139, 92, 246);
        var fg = Color.FromArgb(244, 243, 255);
        var muted = Color.FromArgb(167, 163, 194);

        BackColor = bg;
        ForeColor = fg;
        Font = new Font("Segoe UI", 9.5f);

        var header = new Label
        {
            Text = "EHOT OS — Создание загрузочной флешки (только съёмные USB-диски)",
            Font = new Font("Segoe UI", 12.5f, FontStyle.Bold),
            ForeColor = Color.FromArgb(168, 85, 247),
            Location = new Point(20, 16),
            Size = new Size(720, 28)
        };

        var lblIso = new Label { Text = "1. Образ EHOT OS (.iso или первый том .iso.part.aa):", Location = new Point(20, 56), Size = new Size(500, 22), ForeColor = muted };
        _isoPathBox.SetBounds(20, 82, 580, 28);
        _isoPathBox.BackColor = panelBg;
        _isoPathBox.ForeColor = fg;
        _browseBtn.SetBounds(612, 81, 128, 30);
        _browseBtn.BackColor = panelBg;
        _browseBtn.ForeColor = fg;

        var lblSha = new Label { Text = "Ожидаемый SHA-256 (автоподхват из .sha256 или вручную):", Location = new Point(20, 120), Size = new Size(460, 20), ForeColor = muted };
        _expectedShaBox.SetBounds(20, 144, 720, 26);
        _expectedShaBox.BackColor = panelBg;
        _expectedShaBox.ForeColor = fg;

        _verifyShaCheck.SetBounds(20, 178, 340, 24);
        _verifyShaCheck.ForeColor = fg;

        var lblUsb = new Label { Text = "2. Выберите USB-накопитель (внутренние диски скрыты защитой):", Location = new Point(20, 214), Size = new Size(520, 22), ForeColor = muted };
        _usbCombo.SetBounds(20, 240, 580, 28);
        _usbCombo.BackColor = panelBg;
        _usbCombo.ForeColor = fg;
        _refreshBtn.SetBounds(612, 239, 128, 30);
        _refreshBtn.BackColor = panelBg;
        _refreshBtn.ForeColor = fg;

        _confirmWipeCheck.SetBounds(20, 282, 720, 26);
        _confirmWipeCheck.ForeColor = Color.FromArgb(250, 204, 21);

        _writeBtn.SetBounds(20, 318, 720, 40);
        _writeBtn.BackColor = accent;
        _writeBtn.ForeColor = Color.White;
        _writeBtn.FlatStyle = FlatStyle.Flat;
        _writeBtn.Font = new Font("Segoe UI", 10.5f, FontStyle.Bold);

        _progress.SetBounds(20, 370, 720, 22);
        _statusLabel.SetBounds(20, 398, 720, 22);
        _statusLabel.ForeColor = fg;

        _logBox.SetBounds(20, 428, 720, 114);
        _logBox.BackColor = panelBg;
        _logBox.ForeColor = Color.FromArgb(216, 214, 235);

        Controls.AddRange(new Control[]
        {
            header, lblIso, _isoPathBox, _browseBtn, lblSha, _expectedShaBox,
            _verifyShaCheck, lblUsb, _usbCombo, _refreshBtn, _confirmWipeCheck,
            _writeBtn, _progress, _statusLabel, _logBox
        });

        _browseBtn.Click += (_, _) => SelectIsoFile();
        _refreshBtn.Click += (_, _) => RefreshUsbList();
        _writeBtn.Click += async (_, _) => await StartWriteAsync();

        RefreshUsbList();
    }

    private void AppendLog(string line)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => AppendLog(line));
            return;
        }
        _logBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {line}{Environment.NewLine}");
    }

    private void SelectIsoFile()
    {
        using var ofd = new OpenFileDialog
        {
            Title = "Выберите ISO-образ EHOT OS",
            Filter = "Образ EHOT OS (*.iso;*.iso.part.*)|*.iso;*.iso.part.*|Все файлы (*.*)|*.*"
        };
        if (ofd.ShowDialog(this) != DialogResult.OK)
            return;

        try
        {
            _resolvedFiles = RawIsoWriter.ResolveInputFiles(ofd.FileName);
            _isoPathBox.Text = _resolvedFiles.Count == 1
                ? _resolvedFiles[0]
                : $"{_resolvedFiles[0]} (+ ещё {_resolvedFiles.Count - 1} частей)";
            AppendLog($"Выбран образ ({_resolvedFiles.Count} файл(ов)).");

            var autoSha = RawIsoWriter.TryFindExpectedSha256(_resolvedFiles);
            if (!string.IsNullOrEmpty(autoSha))
            {
                _expectedShaBox.Text = autoSha;
                AppendLog($"Найден файл .sha256: {autoSha}");
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Ошибка выбора образа", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void RefreshUsbList()
    {
        _usbCombo.Items.Clear();
        _disks = UsbDiskService.ListUsbDisks();
        int preferredIndex = 0;
        for (int i = 0; i < _disks.Count; i++)
        {
            _usbCombo.Items.Add(_disks[i].DisplayLabel);
            if (_disks[i].IsLikelyKingstonTarget)
                preferredIndex = i;
        }
        if (_disks.Count > 0)
        {
            _usbCombo.SelectedIndex = preferredIndex;
            AppendLog($"Найдено USB-накопителей: {_disks.Count}");
        }
        else
        {
            AppendLog("Съёмные USB-накопители (>= 4 ГБ) не обнаружены. Вставьте Kingston DataTraveler и нажмите «Обновить USB».");
        }
    }

    private async Task StartWriteAsync()
    {
        if (_resolvedFiles.Count == 0)
        {
            MessageBox.Show(this, "Сначала выберите файл образа EHOT OS (.iso).", "Не выбран образ", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (_usbCombo.SelectedIndex < 0 || _usbCombo.SelectedIndex >= _disks.Count)
        {
            MessageBox.Show(this, "Выберите USB-флешку из списка.", "Не выбрана флешка", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (!_confirmWipeCheck.Checked)
        {
            MessageBox.Show(this, "Поставьте галочку подтверждения очистки выбранной USB-флешки.", "Требуется подтверждение", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var targetDisk = _disks[_usbCombo.SelectedIndex];
        var confirmResult = MessageBox.Show(
            this,
            $"ВНИМАНИЕ! Все данные на носителе будут безвозвратно удалены:\n\n" +
            $"Диск #{targetDisk.DiskIndex}: {targetDisk.Model}\n" +
            $"Объём: {targetDisk.SizeGb:F1} ГБ\n" +
            $"Тома: {(targetDisk.DriveLetters.Count > 0 ? string.Join(", ", targetDisk.DriveLetters) : "нет")}\n\n" +
            "Нажмите «Да» для начала записи.",
            "Последнее предупреждение",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning);

        if (confirmResult != DialogResult.Yes)
            return;

        ToggleControls(false);
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;

        try
        {
            if (_verifyShaCheck.Checked)
            {
                _statusLabel.Text = "Проверка контрольной суммы SHA-256 образа...";
                AppendLog("Вычисление SHA-256 образа...");
                var actualSha = await Task.Run(() =>
                    RawIsoWriter.ComputeStreamSha256(_resolvedFiles, ratio =>
                        BeginInvoke(() => _progress.Value = Math.Clamp((int)(ratio * 1000), 0, 1000)), ct), ct);
                AppendLog($"Вычисленный SHA-256: {actualSha}");

                var expected = _expectedShaBox.Text.Trim().ToLowerInvariant();
                if (!string.IsNullOrEmpty(expected) && expected != actualSha)
                    throw new InvalidDataException($"Контрольная сумма SHA-256 НЕ СОВПАДАЕТ!\nОжидалось: {expected}\nФактически: {actualSha}");
            }

            await Task.Run(() =>
                RawIsoWriter.WriteIsoToUsbDisk(
                    targetDisk,
                    _resolvedFiles,
                    AppendLog,
                    (ratio, text) => BeginInvoke(() =>
                    {
                        _progress.Value = Math.Clamp((int)(ratio * 1000), 0, 1000);
                        _statusLabel.Text = $"Запись на USB: {text}";
                    }),
                    ct), ct);

            _progress.Value = 1000;
            _statusLabel.Text = "Готово! Загрузочная флешка EHOT OS успешно создана.";
            AppendLog("УСПЕХ! Извлеките флешку безопасно и загрузите с неё ноутбук Lenovo.");
            MessageBox.Show(
                this,
                "Загрузочная флешка EHOT OS успешно создана!\n\nБезопасно извлеките Kingston DataTraveler, вставьте в выключенный Lenovo и выберите загрузку с USB (F12 / Fn+F12 / Novo-кнопка).",
                "Готово",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _statusLabel.Text = "Ошибка записи. Подробности в журнале.";
            AppendLog($"ОШИБКА: {ex.Message}");
            MessageBox.Show(this, ex.Message, "Ошибка записи", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            ToggleControls(true);
            RefreshUsbList();
        }
    }

    private void ToggleControls(bool enabled)
    {
        _browseBtn.Enabled = enabled;
        _refreshBtn.Enabled = enabled;
        _usbCombo.Enabled = enabled;
        _verifyShaCheck.Enabled = enabled;
        _confirmWipeCheck.Enabled = enabled;
        _writeBtn.Enabled = enabled;
    }
}
