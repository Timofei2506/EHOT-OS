using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace MfiserliUsbCreator;

internal static class Palette
{
    public static readonly Color Bg = ColorTranslator.FromHtml("#0B1420");
    public static readonly Color Card = ColorTranslator.FromHtml("#0F1B2A");
    public static readonly Color CardBorder = Color.FromArgb(56, 34, 211, 238);
    public static readonly Color Fg = ColorTranslator.FromHtml("#E8F1FA");
    public static readonly Color Muted = ColorTranslator.FromHtml("#9FB6CC");
    public static readonly Color Accent = ColorTranslator.FromHtml("#22D3EE");
    public static readonly Color Accent2 = ColorTranslator.FromHtml("#38BDF8");
    public static readonly Color Deep = ColorTranslator.FromHtml("#0E7490");
    public static readonly Color DeepHover = ColorTranslator.FromHtml("#0891B2");
    public static readonly Color Warn = ColorTranslator.FromHtml("#FACC15");
    public static readonly Color Ok = ColorTranslator.FromHtml("#4ADE80");
    public static readonly Color InputBg = ColorTranslator.FromHtml("#0A1420");
}

internal static class Ui
{
    public static GraphicsPath RoundedPath(Rectangle r, int radius)
    {
        var p = new GraphicsPath();
        if (radius <= 0 || r.Width <= 0 || r.Height <= 0)
        {
            p.AddRectangle(r);
            return p;
        }
        int d = radius * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    public static void StyleButton(Button b, Color back, Color hover, Color fore, float fontSize, bool bold = true)
    {
        b.FlatStyle = FlatStyle.Flat;
        b.FlatAppearance.BorderColor = Palette.CardBorder;
        b.FlatAppearance.BorderSize = 1;
        b.FlatAppearance.MouseOverBackColor = hover;
        b.FlatAppearance.MouseDownBackColor = Palette.Accent;
        b.BackColor = back;
        b.ForeColor = fore;
        b.Font = new Font("Segoe UI", fontSize, bold ? FontStyle.Bold : FontStyle.Regular);
        b.Cursor = Cursors.Hand;
    }

    public static void StyleInput(TextBox tb)
    {
        tb.BorderStyle = BorderStyle.FixedSingle;
        tb.BackColor = Palette.InputBg;
        tb.ForeColor = Palette.Fg;
        tb.Font = new Font("Segoe UI", 9.5f);
    }

    public static void StyleCheck(CheckBox c, Color fore, float size = 9.25f, bool bold = false)
    {
        c.FlatStyle = FlatStyle.Flat;
        c.ForeColor = fore;
        c.Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular);
        c.Cursor = Cursors.Hand;
    }
}

/// <summary>Rounded "glass" card with a step number badge and a title.</summary>
internal sealed class GlassCard : Panel
{
    public string? StepNumber { get; set; }
    public string? Title { get; set; }

    public GlassCard()
    {
        DoubleBuffered = true;
        ResizeRedraw = true;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var path = Ui.RoundedPath(rect, 16))
        {
            using var fill = new SolidBrush(Palette.Card);
            g.FillPath(fill, path);
            using var pen = new Pen(Palette.CardBorder, 1.2f);
            g.DrawPath(pen, path);
        }

        if (!string.IsNullOrEmpty(StepNumber))
        {
            var circle = new Rectangle(14, 10, 32, 32);
            using (var path = Ui.RoundedPath(circle, 16))
            {
                using var b = new SolidBrush(Palette.Deep);
                g.FillPath(b, path);
                using var pen = new Pen(Palette.Accent, 1.4f);
                g.DrawPath(pen, path);
            }
            TextRenderer.DrawText(g, StepNumber, new Font("Segoe UI", 12f, FontStyle.Bold),
                circle, Palette.Accent, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }

        if (!string.IsNullOrEmpty(Title))
        {
            TextRenderer.DrawText(g, Title, new Font("Segoe UI", 11.5f, FontStyle.Bold),
                new Rectangle(58, 12, Width - 70, 28), Palette.Fg,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }
    }
}

/// <summary>Rounded gradient progress bar.</summary>
internal sealed class RoundedProgress : Control
{
    private double _ratio;

    public double Ratio
    {
        get => _ratio;
        set { _ratio = Math.Clamp(value, 0.0, 1.0); Invalidate(); }
    }

    public RoundedProgress()
    {
        DoubleBuffered = true;
        ResizeRedraw = true;
        Height = 22;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var path = Ui.RoundedPath(rect, 10))
        {
            using var bg = new SolidBrush(Palette.InputBg);
            g.FillPath(bg, path);
            using var pen = new Pen(Palette.CardBorder, 1.2f);
            g.DrawPath(pen, path);
        }
        int w = (int)Math.Round((Width - 2) * _ratio);
        if (w > 1)
        {
            var fillRect = new Rectangle(1, 1, Math.Max(w, Height), Height - 2);
            using var path = Ui.RoundedPath(fillRect, 9);
            using var grad = new LinearGradientBrush(new Rectangle(Point.Empty, Size), Palette.Accent2, Palette.Accent, 0f);
            g.FillPath(grad, path);
        }
    }
}

internal sealed class MainForm : Form
{
    private const string AutoIsoPrefix = "mfiserli-os";

    private readonly TextBox _isoPathBox = new();
    private readonly TextBox _expectedShaBox = new();
    private readonly Button _browseBtn = new() { Text = "Выбрать…" };
    private readonly Button _autoFindBtn = new() { Text = "Найти образ" };
    private readonly CheckBox _verifyShaCheck = new() { Checked = true, Text = "Проверять SHA-256 перед записью" };
    private readonly ListBox _usbList = new();
    private readonly Button _refreshBtn = new() { Text = "Обновить" };
    private readonly CheckBox _confirmWipeCheck = new()
    {
        Text = "Я подтверждаю: все данные на выбранной флешке будут стёрты"
    };
    private readonly Button _writeBtn = new() { Text = "ЗАПИСАТЬ НА ФЛЕШКУ" };
    private readonly RoundedProgress _progress = new();
    private readonly Label _pctLabel = new()
    {
        Text = "0%",
        TextAlign = ContentAlignment.MiddleRight,
        ForeColor = Palette.Accent,
        Font = new Font("Segoe UI", 10f, FontStyle.Bold)
    };
    private readonly Label _statusLabel = new() { Text = "Готово к работе.", ForeColor = Palette.Muted };
    private readonly TextBox _logBox = new()
    {
        Multiline = true,
        ReadOnly = true,
        ScrollBars = ScrollBars.Vertical,
        BackColor = Palette.InputBg,
        ForeColor = ColorTranslator.FromHtml("#CFE7F5"),
        Font = new Font("Consolas", 9f),
        BorderStyle = BorderStyle.FixedSingle
    };

    private List<UsbDiskInfo> _disks = new();
    private List<string> _resolvedFiles = new();
    private CancellationTokenSource? _cts;
    private int _recommendedIndex;

    public MainForm()
    {
        Text = "MfiSerli OS · USB Creator";
        ClientSize = new Size(880, 786);
        BackColor = Palette.Bg;
        ForeColor = Palette.Fg;
        Font = new Font("Segoe UI", 9.75f);
        DoubleBuffered = true;
        MinimumSize = new Size(920, 700);
        StartPosition = FormStartPosition.CenterScreen;
        AllowDrop = true;

        // ---- Header ----
        var logo = new Panel { Bounds = new Rectangle(24, 18, 64, 64) };
        logo.Paint += (_, e) =>
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var r = new Rectangle(0, 0, 63, 63);
            using (var path = Ui.RoundedPath(r, 14))
            {
                using var grad = new LinearGradientBrush(r, ColorTranslator.FromHtml("#12344F"), ColorTranslator.FromHtml("#07101C"), 75f);
                e.Graphics.FillPath(grad, path);
                using var pen = new Pen(Color.FromArgb(70, Color.White), 1.4f);
                e.Graphics.DrawPath(pen, path);
            }
            TextRenderer.DrawText(e.Graphics, "M", new Font("Segoe UI", 24f, FontStyle.Bold),
                r, ColorTranslator.FromHtml("#EEF9FF"),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        };
        var title = new Label
        {
            Text = "MfiSerli OS — USB Creator",
            Font = new Font("Segoe UI", 16.5f, FontStyle.Bold),
            ForeColor = Palette.Fg,
            Bounds = new Rectangle(104, 20, 560, 34)
        };
        var subtitle = new Label
        {
            Text = "Безопасная запись загрузочной флешки · Public Edition (Dark Glass)",
            ForeColor = Palette.Muted,
            Bounds = new Rectangle(106, 56, 560, 24)
        };

        // ---- Card 1: image ----
        var cardImage = new GlassCard
        {
            Bounds = new Rectangle(20, 94, 840, 150),
            StepNumber = "1",
            Title = "Выберите образ MfiSerli OS (.iso или его первую часть)"
        };
        var lblSha = new Label
        {
            Text = "Ожидаемый SHA-256 (подставляется из .sha256 автоматически):",
            ForeColor = Palette.Muted,
            Bounds = new Rectangle(64, 44, 560, 20)
        };
        _isoPathBox.Bounds = new Rectangle(64, 70, 540, 30);
        _browseBtn.Bounds = new Rectangle(612, 69, 104, 32);
        _autoFindBtn.Bounds = new Rectangle(722, 69, 92, 32);
        _expectedShaBox.Bounds = new Rectangle(64, 110, 470, 26);
        _verifyShaCheck.Bounds = new Rectangle(544, 111, 270, 24);
        cardImage.Controls.AddRange(new Control[] { lblSha, _isoPathBox, _browseBtn, _autoFindBtn, _expectedShaBox, _verifyShaCheck });

        // ---- Card 2: USB target ----
        var cardUsb = new GlassCard
        {
            Bounds = new Rectangle(20, 256, 840, 200),
            StepNumber = "2",
            Title = "Вставьте USB-флешку (от 8 ГБ) и выберите её в списке"
        };
        _usbList.Bounds = new Rectangle(64, 44, 660, 106);
        _usbList.DrawMode = DrawMode.OwnerDrawFixed;
        _usbList.ItemHeight = 48;
        _usbList.BorderStyle = BorderStyle.None;
        _usbList.BackColor = Palette.InputBg;
        _usbList.ForeColor = Palette.Fg;
        _usbList.DrawItem += UsbList_DrawItem;
        _usbList.SelectedIndexChanged += (_, _) => { _usbList.Invalidate(); };
        _refreshBtn.Bounds = new Rectangle(736, 44, 78, 32);
        var usbHint = new Label
        {
            Text = "Показываются только съёмные USB-носители ≥ 4 ГБ. Внутренние диски и USB-флешка с Live-образом исключены защитой.",
            ForeColor = Palette.Muted,
            Font = new Font("Segoe UI", 8.5f),
            Bounds = new Rectangle(64, 156, 750, 34)
        };
        cardUsb.Controls.AddRange(new Control[] { _usbList, _refreshBtn, usbHint });

        // ---- Card 3: write ----
        var cardWrite = new GlassCard
        {
            Bounds = new Rectangle(20, 468, 840, 122),
            StepNumber = "3",
            Title = "Запись образа на флешку"
        };
        _confirmWipeCheck.Bounds = new Rectangle(64, 32, 740, 24);
        _writeBtn.Bounds = new Rectangle(64, 62, 520, 44);
        var writeHint = new Label
        {
            Text = "Перед записью: проверка SHA-256.\nПосле записи: верификация загрузочных секторов.",
            ForeColor = Palette.Muted,
            Font = new Font("Segoe UI", 8.5f),
            Bounds = new Rectangle(596, 62, 226, 44)
        };
        cardWrite.Controls.AddRange(new Control[] { _confirmWipeCheck, _writeBtn, writeHint });

        // ---- Progress / status / log ----
        _progress.Bounds = new Rectangle(20, 602, 700, 22);
        _pctLabel.Bounds = new Rectangle(726, 600, 134, 24);
        _statusLabel.Bounds = new Rectangle(20, 632, 840, 22);
        _logBox.Bounds = new Rectangle(20, 660, 840, 104);

        Controls.AddRange(new Control[]
        {
            logo, title, subtitle, cardImage, cardUsb, cardWrite,
            _progress, _pctLabel, _statusLabel, _logBox
        });

        Ui.StyleInput(_isoPathBox);
        Ui.StyleInput(_expectedShaBox);
        Ui.StyleButton(_browseBtn, Palette.Card, Palette.DeepHover, Palette.Fg, 9.5f, bold: false);
        Ui.StyleButton(_autoFindBtn, Palette.Card, Palette.DeepHover, Palette.Accent, 9.5f, bold: false);
        Ui.StyleCheck(_verifyShaCheck, Palette.Muted);
        Ui.StyleButton(_refreshBtn, Palette.Card, Palette.DeepHover, Palette.Fg, 9.5f, bold: false);
        Ui.StyleCheck(_confirmWipeCheck, Palette.Warn);
        Ui.StyleButton(_writeBtn, Palette.Deep, Palette.DeepHover, Color.White, 12f, bold: true);

        _browseBtn.Click += (_, _) => SelectIsoFile();
        _autoFindBtn.Click += (_, _) => TryAutoFind(verbose: true);
        _refreshBtn.Click += (_, _) => RefreshUsbList();
        _writeBtn.Click += async (_, _) => await StartWriteAsync();
        DragEnter += MainForm_DragEnter;
        DragDrop += MainForm_DragDrop;

        Shown += async (_, _) =>
        {
            RefreshUsbList();
            await Task.Delay(150);
            TryAutoFind(verbose: false);
        };
    }

    private void UsbList_DrawItem(object? sender, DrawItemEventArgs e)
    {
        if (e.Index < 0 || e.Index >= _disks.Count)
            return;
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        bool selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
        var rect = new Rectangle(e.Bounds.X + 3, e.Bounds.Y + 3, e.Bounds.Width - 6, e.Bounds.Height - 6);

        using (var path = Ui.RoundedPath(rect, 10))
        {
            using var fill = new SolidBrush(selected ? Color.FromArgb(70, 34, 211, 238) : Palette.Card);
            g.FillPath(fill, path);
            using var pen = new Pen(selected ? Palette.Accent : Palette.CardBorder, 1.2f);
            g.DrawPath(pen, path);
        }

        var disk = _disks[e.Index];
        var glyph = new Rectangle(rect.X + 10, rect.Y + rect.Height / 2 - 14, 48, 28);
        using (var path = Ui.RoundedPath(glyph, 8))
        {
            using var b = new SolidBrush(Color.FromArgb(60, 14, 116, 144));
            g.FillPath(b, path);
            using var pen = new Pen(Palette.Accent, 1.3f);
            g.DrawPath(pen, path);
        }
        TextRenderer.DrawText(g, "USB", new Font("Segoe UI", 7.5f, FontStyle.Bold),
            glyph, Palette.Accent, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);

        var letters = disk.DriveLetters.Count > 0 ? string.Join(", ", disk.DriveLetters) : "без буквы";
        TextRenderer.DrawText(g, disk.Model, new Font("Segoe UI", 10f, FontStyle.Bold),
            new Rectangle(rect.X + 70, rect.Y + 4, rect.Width - 200, 22), Palette.Fg,
            TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
        TextRenderer.DrawText(g, $"{disk.SizeGb:F1} ГБ · тома: {letters} · Диск #{disk.DiskIndex}",
            new Font("Segoe UI", 8.5f),
            new Rectangle(rect.X + 70, rect.Y + 24, rect.Width - 200, 20), Palette.Muted,
            TextFormatFlags.Left | TextFormatFlags.EndEllipsis);

        if (e.Index == _recommendedIndex && _disks.Count > 1)
        {
            var pill = new Rectangle(rect.Right - 128, rect.Y + rect.Height / 2 - 11, 116, 22);
            using (var path = Ui.RoundedPath(pill, 11))
            {
                using var b = new SolidBrush(Palette.Deep);
                g.FillPath(b, path);
            }
            TextRenderer.DrawText(g, "★ рекомендую", new Font("Segoe UI", 8f, FontStyle.Bold),
                pill, Palette.Accent, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }

    private void MainForm_DragEnter(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetDataPresent(DataFormats.FileDrop) == true)
            e.Effect = DragDropEffects.Copy;
    }

    private void MainForm_DragDrop(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetData(DataFormats.FileDrop) is not string[] files || files.Length == 0)
            return;
        UseImagePath(files[0]);
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

    private void UseImagePath(string path)
    {
        try
        {
            _resolvedFiles = RawIsoWriter.ResolveInputFiles(path);
            _isoPathBox.Text = _resolvedFiles.Count == 1
                ? _resolvedFiles[0]
                : $"{_resolvedFiles[0]} (+ ещё {_resolvedFiles.Count - 1} частей)";
            AppendLog($"Образ выбран ({_resolvedFiles.Count} файл(ов)): {Path.GetFileName(_resolvedFiles[0])}");
            _isoPathBox.ForeColor = Palette.Fg;

            var autoSha = RawIsoWriter.TryFindExpectedSha256(_resolvedFiles);
            if (!string.IsNullOrEmpty(autoSha))
            {
                _expectedShaBox.Text = autoSha;
                AppendLog($"Найден .sha256: {autoSha}");
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Ошибка выбора образа", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void SelectIsoFile()
    {
        using var ofd = new OpenFileDialog
        {
            Title = "Выберите ISO-образ MfiSerli OS",
            Filter = "Образ MfiSerli OS (*.iso;*.iso.part.*)|*.iso;*.iso.part.*|Все файлы (*.*)|*.*"
        };
        if (ofd.ShowDialog(this) != DialogResult.OK)
            return;
        UseImagePath(ofd.FileName);
    }

    private void TryAutoFind(bool verbose)
    {
        var dirs = new List<string>
        {
            AppContext.BaseDirectory,
            Environment.CurrentDirectory,
            Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        };
        var candidates = dirs.Where(Directory.Exists)
            .SelectMany(d => Directory.EnumerateFiles(d, "*", SearchOption.TopDirectoryOnly))
            .Where(f => (f.EndsWith(".iso", StringComparison.OrdinalIgnoreCase)
                         || f.EndsWith(".iso.part.aa", StringComparison.OrdinalIgnoreCase))
                        && !f.EndsWith(".sha256", StringComparison.OrdinalIgnoreCase))
            .Distinct()
            .ToList();

        if (candidates.Count == 0)
        {
            if (verbose)
                AppendLog("Образ не найден автоматически — выберите файл вручную или перетащите .iso в окно.");
            return;
        }

        var best = candidates
            .OrderByDescending(f => Path.GetFileName(f).StartsWith(AutoIsoPrefix, StringComparison.OrdinalIgnoreCase) ? 2
                                    : Path.GetFileName(f).Contains("mfiserli", StringComparison.OrdinalIgnoreCase) ? 1 : 0)
            .ThenByDescending(f => new FileInfo(f).LastWriteTimeUtc)
            .First();
        UseImagePath(best);
        if (verbose)
            AppendLog($"Найден автоматически: {best}");
    }

    private void RefreshUsbList()
    {
        _usbList.Items.Clear();
        _disks = UsbDiskService.ListUsbDisks();
        _recommendedIndex = 0;
        for (int i = 0; i < _disks.Count; i++)
        {
            _usbList.Items.Add(_disks[i].Model);
            if (_disks[i].SizeBytes > _disks[_recommendedIndex].SizeBytes)
                _recommendedIndex = i;
        }
        if (_disks.Count > 0)
        {
            _usbList.SelectedIndex = _recommendedIndex;
            AppendLog($"Найдено USB-накопителей: {_disks.Count}.");
        }
        else
        {
            AppendLog("Съёмные USB-накопители (>= 4 ГБ) не обнаружены. Вставьте флешку и нажмите «Обновить».");
        }
        _usbList.Invalidate();
    }

    private async Task StartWriteAsync()
    {
        if (_resolvedFiles.Count == 0)
        {
            MessageBox.Show(this, "Сначала выберите файл образа MfiSerli OS (.iso).", "Не выбран образ",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (_usbList.SelectedIndex < 0 || _usbList.SelectedIndex >= _disks.Count)
        {
            MessageBox.Show(this, "Выберите USB-флешку из списка.", "Не выбрана флешка",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (!_confirmWipeCheck.Checked)
        {
            MessageBox.Show(this, "Поставьте галочку подтверждения очистки выбранной USB-флешки.", "Требуется подтверждение",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var targetDisk = _disks[_usbList.SelectedIndex];
        var confirm = MessageBox.Show(
            this,
            "ВНИМАНИЕ! Все данные на носителе будут безвозвратно удалены:\n\n" +
            $"Диск #{targetDisk.DiskIndex}: {targetDisk.Model}\n" +
            $"Объём: {targetDisk.SizeGb:F1} ГБ\n" +
            $"Тома: {(targetDisk.DriveLetters.Count > 0 ? string.Join(", ", targetDisk.DriveLetters) : "нет")}\n\n" +
            "Продолжить запись MfiSerli OS?",
            "Последнее предупреждение",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning);

        if (confirm != DialogResult.Yes)
            return;

        ToggleControls(false);
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        var sw = System.Diagnostics.Stopwatch.StartNew();

        try
        {
            if (_verifyShaCheck.Checked)
            {
                SetProgress(0.0);
                _statusLabel.Text = "Проверка контрольной суммы SHA-256 образа…";
                AppendLog("Вычисление SHA-256 образа…");
                var actualSha = await Task.Run(() =>
                    RawIsoWriter.ComputeStreamSha256(_resolvedFiles, ratio => SafeProgress(ratio), ct), ct);
                AppendLog($"Вычисленный SHA-256: {actualSha}");

                var expected = _expectedShaBox.Text.Trim().ToLowerInvariant();
                if (!string.IsNullOrEmpty(expected) && expected != actualSha)
                    throw new InvalidDataException(
                        $"Контрольная сумма SHA-256 НЕ СОВПАДАЕТ!\nОжидалось: {expected}\nФактически: {actualSha}");
                AppendLog("SHA-256 совпадает — образ цел.");
            }

            _statusLabel.Text = "Запись на USB-флешку…";
            await Task.Run(() =>
                RawIsoWriter.WriteIsoToUsbDisk(
                    targetDisk,
                    _resolvedFiles,
                    AppendLog,
                    (ratio, text) => SafeProgress(ratio, text),
                    ct), ct);

            SetProgress(1.0);
            _statusLabel.Text = $"Готово за {sw.Elapsed.TotalSeconds:0} сек! Загрузочная флешка MfiSerli OS создана.";
            _statusLabel.ForeColor = Palette.Ok;
            AppendLog("УСПЕХ! Безопасно извлеките флешку, вставьте в выключенный ПК и откройте Boot Menu (F12 / Fn+F12 / Novo).");
            MessageBox.Show(
                this,
                "Загрузочная флешка MfiSerli OS успешно создана!\n\n" +
                "1. Безопасно извлеките флешку.\n" +
                "2. Вставьте в выключенный компьютер.\n" +
                "3. Откройте Boot Menu (F12 / Fn+F12 / кнопка Novo) и выберите USB.\n\n" +
                "В Live-системе нажмите «Установить MfiSerli OS» на рабочем столе.",
                "Готово",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _statusLabel.Text = "Ошибка записи. Подробности в журнале ниже.";
            _statusLabel.ForeColor = ColorTranslator.FromHtml("#F87171");
            AppendLog($"ОШИБКА: {ex.Message}");
            MessageBox.Show(this, ex.Message, "Ошибка записи", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            ToggleControls(true);
            RefreshUsbList();
        }
    }

    private void SafeProgress(double ratio, string? text = null)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => SafeProgress(ratio, text));
            return;
        }
        SetProgress(ratio);
        _statusLabel.Text = text is null
            ? "Проверка SHA-256…"
            : $"Запись на USB: {text}";
    }

    private void SetProgress(double ratio)
    {
        _progress.Ratio = ratio;
        _pctLabel.Text = $"{Math.Round(ratio * 100)}%";
    }

    private void ToggleControls(bool enabled)
    {
        _browseBtn.Enabled = enabled;
        _autoFindBtn.Enabled = enabled;
        _refreshBtn.Enabled = enabled;
        _usbList.Enabled = enabled;
        _verifyShaCheck.Enabled = enabled;
        _confirmWipeCheck.Enabled = enabled;
        _writeBtn.Enabled = enabled;
        _writeBtn.BackColor = enabled ? Palette.Deep : Palette.Card;
        if (enabled)
            _statusLabel.ForeColor = Palette.Muted;
    }
}
