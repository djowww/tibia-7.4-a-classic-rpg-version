using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace AntigasLauncher;

// Drawing of the "Watchtower" launcher: the stone wall, torches and gold of the
// site banner (site/classic-assets/wall.svg and torch.svg), painted natively.
internal static class WatchtowerArt
{
    internal static readonly Color Night = Color.FromArgb(8, 9, 7);
    internal static readonly Color Stone = Color.FromArgb(66, 70, 63);
    internal static readonly Color StoneDark = Color.FromArgb(40, 44, 36);
    internal static readonly Color StoneDeep = Color.FromArgb(23, 25, 18);
    internal static readonly Color StoneEdge = Color.FromArgb(133, 132, 116);
    internal static readonly Color Gold = Color.FromArgb(225, 199, 121);
    internal static readonly Color GoldStrong = Color.FromArgb(231, 197, 70);
    internal static readonly Color GoldDeep = Color.FromArgb(177, 154, 95);
    internal static readonly Color Parchment = Color.FromArgb(251, 236, 201);
    internal static readonly Color ParchmentEdge = Color.FromArgb(201, 174, 100);
    internal static readonly Color Ink = Color.FromArgb(80, 53, 28);
    internal static readonly Color Wine = Color.FromArgb(116, 9, 0);
    internal static readonly Color Light = Color.FromArgb(245, 238, 227);
    internal static readonly Color Dim = Color.FromArgb(189, 183, 162);
    internal static readonly Color Ok = Color.FromArgb(143, 208, 106);
    internal static readonly Color Busy = Color.FromArgb(255, 210, 74);
    internal static readonly Color Bad = Color.FromArgb(232, 100, 84);
    internal static readonly Color Idle = Color.FromArgb(141, 143, 128);

    private static readonly Color[] Bricks =
    [
        Color.FromArgb(61, 64, 58), Color.FromArgb(71, 74, 66), Color.FromArgb(53, 55, 47),
        Color.FromArgb(65, 68, 60), Color.FromArgb(76, 79, 70), Color.FromArgb(58, 61, 54),
    ];

    // Rows of bricks 20 px high with 2 px of mortar, like wall.svg, with a soft grain.
    internal static Bitmap MakeWall(int width, int height)
    {
        var image = new Bitmap(width, height);
        var random = new Random(74);
        using (var g = Graphics.FromImage(image))
        {
            g.Clear(Color.FromArgb(23, 24, 20));
            using var highlight = new SolidBrush(Color.FromArgb(33, 255, 255, 255));
            using var shadow = new SolidBrush(Color.FromArgb(71, 0, 0, 0));
            for (var y = 1; y < height; y += 22)
            {
                var x = -random.Next(10, 70);
                while (x < width)
                {
                    var brick = random.Next(58, 104);
                    using (var fill = new SolidBrush(Bricks[random.Next(Bricks.Length)])) g.FillRectangle(fill, x, y, brick, 20);
                    g.FillRectangle(highlight, x, y, brick, 1);
                    g.FillRectangle(shadow, x, y + 18, brick, 2);
                    x += brick + 2;
                }
            }
        }
        AddGrain(image, random, 7);
        return image;
    }

    internal static Bitmap MakeStone(int width, int height)
    {
        var image = new Bitmap(width, height);
        using (var g = Graphics.FromImage(image)) g.Clear(Stone);
        var random = new Random(2004);
        AddGrain(image, random, 6);
        return image;
    }

    private static void AddGrain(Bitmap image, Random random, int variation)
    {
        for (var y = 0; y < image.Height; y++)
        for (var x = 0; x < image.Width; x++)
        {
            var color = image.GetPixel(x, y);
            var shade = random.Next(-variation, variation + 1);
            image.SetPixel(x, y, Color.FromArgb(Math.Clamp(color.R + shade, 0, 255),
                Math.Clamp(color.G + shade, 0, 255), Math.Clamp(color.B + shade, 0, 255)));
        }
    }

    // Darkens the wall away from the point the torches light.
    internal static void Vignette(Graphics g, RectangleF bounds, PointF center)
    {
        using var path = new GraphicsPath();
        var reach = Math.Max(bounds.Width, bounds.Height) * 1.05F;
        path.AddEllipse(center.X - reach, center.Y - reach * .8F, reach * 2, reach * 1.6F);
        using var brush = new PathGradientBrush(path)
        {
            CenterPoint = center,
            CenterColor = Color.FromArgb(0, 0, 0, 0),
            SurroundColors = [Color.FromArgb(215, 0, 0, 0)],
            FocusScales = new PointF(.12F, .12F),
        };
        var state = g.Save();
        g.SetClip(bounds);
        using (var edge = new SolidBrush(Color.FromArgb(215, 0, 0, 0)))
        using (var outside = new Region(bounds))
        {
            outside.Exclude(path);
            g.FillRegion(edge, outside);
        }
        g.FillPath(brush, path);
        g.Restore(state);
    }

    // torch.svg: 9 x 22 units. The flame flickers over four frames.
    internal static void Torch(Graphics g, float x, float y, float unit, int frame)
    {
        using (var glowPath = new GraphicsPath())
        {
            var radius = unit * (15 + (frame % 2));
            glowPath.AddEllipse(x + unit * 4.5F - radius, y + unit * 5 - radius, radius * 2, radius * 2);
            using var glow = new PathGradientBrush(glowPath)
            {
                CenterColor = Color.FromArgb(110, 232, 100, 27),
                SurroundColors = [Color.FromArgb(0, 232, 100, 27)],
            };
            g.FillPath(glow, glowPath);
        }
        var state = g.Save();
        var (scaleY, shift) = (frame % 4) switch { 1 => (.84F, .4F), 2 => (1.1F, 0F), 3 => (.92F, -.4F), _ => (1F, 0F) };
        g.TranslateTransform(x + shift * unit, y + 8 * unit * (1 - scaleY));
        g.ScaleTransform(unit, unit * scaleY);
        Fill(g, 232, 100, 27, 4, 0, 1, 2); Fill(g, 232, 100, 27, 3, 2, 3, 6); Fill(g, 232, 100, 27, 2, 4, 5, 4);
        Fill(g, 255, 210, 74, 4, 2, 1, 2); Fill(g, 255, 210, 74, 3, 4, 3, 4); Fill(g, 255, 246, 201, 4, 5, 1, 3);
        g.Restore(state);
        state = g.Save();
        g.TranslateTransform(x, y);
        g.ScaleTransform(unit, unit);
        Fill(g, 154, 138, 102, 1, 8, 7, 1); Fill(g, 95, 86, 68, 2, 9, 5, 2); Fill(g, 90, 58, 28, 3, 11, 3, 9);
        Fill(g, 128, 86, 47, 3, 11, 1, 9); Fill(g, 38, 34, 28, 2, 15, 5, 1); Fill(g, 59, 39, 19, 4, 20, 1, 2);
        g.Restore(state);
    }

    private static void Fill(Graphics g, int red, int green, int blue, float x, float y, float width, float height)
    {
        using var brush = new SolidBrush(Color.FromArgb(red, green, blue));
        g.FillRectangle(brush, x, y, width, height);
    }

    // The site wordmark: gold italic Georgia with a light edge above and a dark shadow below.
    internal static void Wordmark(Graphics g, string text, float centerX, float top, float size)
    {
        using var family = new FontFamily("Georgia");
        using var format = new StringFormat(StringFormat.GenericTypographic) { Alignment = StringAlignment.Center };
        using var path = new GraphicsPath();
        path.AddString(text, family, (int)(FontStyle.Bold | FontStyle.Italic), size, new PointF(centerX, top), format);
        Layer(g, path, 2, 3, Color.FromArgb(7, 5, 0));
        Layer(g, path, -1, -1, Color.FromArgb(255, 240, 166));
        Layer(g, path, 0, 0, GoldStrong);
    }

    private static void Layer(Graphics g, GraphicsPath path, float dx, float dy, Color color)
    {
        var state = g.Save();
        g.TranslateTransform(dx, dy);
        using var brush = new SolidBrush(color);
        g.FillPath(brush, path);
        g.Restore(state);
    }

    // Text with wide letter spacing, centered on centerX.
    internal static void Spaced(Graphics g, string text, Font font, Color color, float centerX, float y, float spacing)
    {
        using var format = new StringFormat(StringFormat.GenericTypographic) { FormatFlags = StringFormatFlags.MeasureTrailingSpaces };
        var widths = text.Select(c => g.MeasureString(c.ToString(), font, PointF.Empty, format).Width).ToArray();
        var x = centerX - (widths.Sum() + spacing * (text.Length - 1)) / 2;
        using var shadow = new SolidBrush(Night);
        using var brush = new SolidBrush(color);
        for (var i = 0; i < text.Length; i++)
        {
            g.DrawString(text[i].ToString(), font, shadow, x + 1, y + 1, format);
            g.DrawString(text[i].ToString(), font, brush, x, y, format);
            x += widths[i] + spacing;
        }
    }

    internal static void ShadowText(Graphics g, string text, Font font, Color color, RectangleF bounds, StringFormat format)
    {
        using var shadow = new SolidBrush(Color.FromArgb(16, 17, 14));
        using var brush = new SolidBrush(color);
        var lower = bounds;
        lower.Offset(1, 2);
        g.DrawString(text, font, shadow, lower, format);
        g.DrawString(text, font, brush, bounds, format);
    }

    // CSS "ridge" border, two pixels: raised outside, sunk inside.
    internal static void Ridge(Graphics g, RectangleF bounds, Color light, Color dark)
    {
        Frame(g, bounds, light, dark);
        Frame(g, RectangleF.Inflate(bounds, -1, -1), dark, light);
    }

    private static void Frame(Graphics g, RectangleF r, Color topLeft, Color bottomRight)
    {
        using var first = new SolidBrush(topLeft);
        using var second = new SolidBrush(bottomRight);
        g.FillRectangle(first, r.Left, r.Top, r.Width, 1);
        g.FillRectangle(first, r.Left, r.Top, 1, r.Height);
        g.FillRectangle(second, r.Left, r.Bottom - 1, r.Width, 1);
        g.FillRectangle(second, r.Right - 1, r.Top, 1, r.Height);
    }

    internal static void Shield(Graphics g, RectangleF bounds, bool active)
    {
        float X(float v) => bounds.Left + v / 22F * bounds.Width;
        float Y(float v) => bounds.Top + v / 26F * bounds.Height;
        using var body = new GraphicsPath();
        body.AddLine(X(11), Y(1), X(20.5F), Y(4));
        body.AddLine(X(20.5F), Y(4), X(20.5F), Y(12));
        body.AddBezier(X(20.5F), Y(12), X(20.5F), Y(18), X(16.5F), Y(22.5F), X(11), Y(25));
        body.AddBezier(X(11), Y(25), X(5.5F), Y(22.5F), X(1.5F), Y(18), X(1.5F), Y(12));
        body.AddLine(X(1.5F), Y(12), X(1.5F), Y(4));
        body.CloseFigure();
        using (var fill = new LinearGradientBrush(bounds, Color.White, Color.Black, LinearGradientMode.Vertical))
        {
            fill.InterpolationColors = active
                ? new ColorBlend { Colors = [Color.FromArgb(246, 227, 154), Color.FromArgb(210, 171, 72), Color.FromArgb(143, 106, 28)], Positions = [0F, .55F, 1F] }
                : new ColorBlend { Colors = [Color.FromArgb(132, 135, 120), Color.FromArgb(104, 107, 94), Color.FromArgb(78, 81, 70)], Positions = [0F, .55F, 1F] };
            g.FillPath(fill, body);
        }
        var stroke = Math.Max(1.2F, bounds.Width / 18F);
        using var outline = new Pen(Color.FromArgb(28, 21, 10), stroke) { LineJoin = LineJoin.Round };
        g.DrawPath(outline, body);
        using var check = new Pen(Color.FromArgb(28, 21, 10), stroke * 1.9F) { LineJoin = LineJoin.Miter };
        g.DrawLines(check, [new PointF(X(6.2F), Y(12.8F)), new PointF(X(9.7F), Y(16.3F)), new PointF(X(16), Y(9.2F))]);
    }
}

// The gold Play button of the site banner palette.
internal sealed class GoldButton : Button
{
    private bool _hovered, _pressed;

    internal GoldButton()
    {
        FlatStyle = FlatStyle.Flat;
        Cursor = Cursors.Hand;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
            ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        var scale = DeviceDpi / 96F;
        var bounds = new RectangleF(0, 0, Width, Height);
        if (Enabled)
        {
            using var fill = new LinearGradientBrush(bounds, Color.White, Color.Black, LinearGradientMode.Vertical)
            {
                InterpolationColors = new ColorBlend
                {
                    Colors = _hovered && !_pressed
                        ? [Color.FromArgb(255, 240, 178), Color.FromArgb(226, 188, 88), Color.FromArgb(176, 136, 46)]
                        : [Color.FromArgb(246, 227, 154), Color.FromArgb(210, 171, 72), Color.FromArgb(160, 122, 37)],
                    Positions = [0F, .52F, 1F],
                },
            };
            g.FillRectangle(fill, bounds);
        }
        else
        {
            using var fill = new SolidBrush(WatchtowerArt.StoneDark);
            g.FillRectangle(fill, bounds);
        }
        var depth = Math.Max(2, (int)Math.Round(2 * scale));
        var light = Enabled ? Color.FromArgb(255, 244, 190) : WatchtowerArt.StoneEdge;
        var dark = Enabled ? Color.FromArgb(93, 66, 18) : Color.FromArgb(21, 25, 18);
        ClassicLauncherTheme.Bevel(g, ClientRectangle, _pressed ? dark : light, _pressed ? light : dark, depth);
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap };
        var text = bounds;
        if (_pressed) text.Offset(0, scale * 2);
        if (Enabled)
        {
            var glint = text;
            glint.Offset(0, scale);
            using var edge = new SolidBrush(Color.FromArgb(255, 240, 166));
            g.DrawString(Text, Font, edge, glint, format);
        }
        using var ink = new SolidBrush(Enabled ? Color.FromArgb(42, 28, 6) : WatchtowerArt.Gold);
        g.DrawString(Text, Font, ink, text, format);
        if (Focused && ShowFocusCues && Enabled)
            ControlPaint.DrawFocusRectangle(g, Rectangle.Inflate(ClientRectangle, -depth - 3, -depth - 3));
    }

    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hovered = true; Invalidate(); }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hovered = false; _pressed = false; Invalidate(); }
    protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); if (e.Button == MouseButtons.Left) _pressed = true; Invalidate(); }
    protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); _pressed = false; Invalidate(); }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); _pressed = false; Invalidate(); }
    protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); _pressed = false; Invalidate(); }
}
