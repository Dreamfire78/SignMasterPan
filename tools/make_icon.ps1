# Generates the SignMasterPan icon (white mouse with highlighted wheel and four pan arrows).
#   powershell -ExecutionPolicy Bypass -File tools\make_icon.ps1 -OutIco SignMasterPan.ico
#   powershell -ExecutionPolicy Bypass -File tools\make_icon.ps1 -OutIco SignMasterPan_off.ico -Gray
# -Gray creates the "disabled" variant used for the tray while all functions are switched off.
param(
    [Parameter(Mandatory = $true)][string]$OutIco,
    [string]$Preview = "",
    [switch]$Gray
)
Add-Type -AssemblyName System.Drawing

if ($Gray) {
    $colTop = [Drawing.Color]::FromArgb(255, 165, 165, 165)
    $colBottom = [Drawing.Color]::FromArgb(255, 105, 105, 105)
    $colWheel = [Drawing.Color]::FromArgb(255, 120, 120, 120)
    $colLine = [Drawing.Color]::FromArgb(255, 105, 105, 105)
} else {
    $colTop = [Drawing.Color]::FromArgb(255, 58, 139, 240)
    $colBottom = [Drawing.Color]::FromArgb(255, 22, 72, 160)
    $colWheel = [Drawing.Color]::FromArgb(255, 255, 150, 20)
    $colLine = [Drawing.Color]::FromArgb(255, 22, 72, 160)
}

function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Draw-Icon([int]$s) {
    $bmp = New-Object Drawing.Bitmap $s, $s, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([Drawing.Color]::Transparent)

    # Background: rounded square with a vertical gradient
    $inset = [Math]::Max(0.5, $s * 0.03)
    $bg = New-RoundRect $inset $inset ($s - 2 * $inset) ($s - 2 * $inset) ($s * 0.2)
    $rect = New-Object Drawing.RectangleF 0, 0, $s, $s
    $grad = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, $colTop, $colBottom, 90
    $g.FillPath($grad, $bg)

    $white = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
    $c = $s / 2

    # Arrow heads in all four directions
    $tip = $s * 0.08
    $len = $s * 0.13
    $half = $s * 0.10
    $arrows = @(
        @(@($c, $tip), @(($c - $half), ($tip + $len)), @(($c + $half), ($tip + $len))),
        @(@($c, ($s - $tip)), @(($c - $half), ($s - $tip - $len)), @(($c + $half), ($s - $tip - $len))),
        @(@($tip, $c), @(($tip + $len), ($c - $half)), @(($tip + $len), ($c + $half))),
        @(@(($s - $tip), $c), @(($s - $tip - $len), ($c - $half)), @(($s - $tip - $len), ($c + $half)))
    )
    foreach ($a in $arrows) {
        $pts = [Drawing.PointF[]]@(
            (New-Object Drawing.PointF $a[0][0], $a[0][1]),
            (New-Object Drawing.PointF $a[1][0], $a[1][1]),
            (New-Object Drawing.PointF $a[2][0], $a[2][1]))
        $g.FillPolygon($white, $pts)
    }

    # Mouse in the center
    $mw = $s * 0.30; $mh = $s * 0.42
    $mx = $c - $mw / 2; $my = $c - $mh / 2
    $mouse = New-RoundRect $mx $my $mw $mh ($mw / 2 - 0.01)
    $g.FillPath($white, $mouse)

    # Button separator lines from 32 px on
    if ($s -ge 32) {
        $pen = New-Object Drawing.Pen $colLine, ([Math]::Max(1, $s * 0.018))
        $split = $my + $mh * 0.42
        $g.DrawLine($pen, $c, $my + 1, $c, $split)
        $g.DrawLine($pen, $mx + 1, $split, $mx + $mw - 1, $split)
        $pen.Dispose()
    }

    # Highlighted mouse wheel
    $ww = [Math]::Max(2, $s * 0.075); $wh = [Math]::Max(3, $s * 0.14)
    $wheel = New-RoundRect ($c - $ww / 2) ($my + $mh * 0.12) $ww $wh ($ww / 2 - 0.01)
    $g.FillPath((New-Object Drawing.SolidBrush $colWheel), $wheel)

    $g.Dispose()
    return $bmp
}

# ICO entry as DIB (32 bpp + AND mask)
function Get-DibBytes([Drawing.Bitmap]$bmp) {
    $s = $bmp.Width
    $ms = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter $ms
    $bw.Write([uint32]40); $bw.Write([int32]$s); $bw.Write([int32]($s * 2))
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]0)
    $bw.Write([uint32]0); $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([uint32]0); $bw.Write([uint32]0)
    for ($y = $s - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $s; $x++) {
            $p = $bmp.GetPixel($x, $y)
            $bw.Write([byte]$p.B); $bw.Write([byte]$p.G); $bw.Write([byte]$p.R); $bw.Write([byte]$p.A)
        }
    }
    $maskRow = [int]([Math]::Ceiling($s / 32) * 4)
    $bw.Write((New-Object byte[] ($maskRow * $s)))
    $bw.Flush()
    return , $ms.ToArray()
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$images = @()
foreach ($s in $sizes) {
    $bmp = Draw-Icon $s
    if ($s -eq 256) {
        $ms = New-Object IO.MemoryStream
        $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
        $data = $ms.ToArray()
    } else {
        $data = Get-DibBytes $bmp
    }
    $images += , @($s, $data, $bmp)
}

# Write the ICO file
$fs = [IO.File]::Create($OutIco)
$w = New-Object IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($img in $images) {
    $s = $img[0]; $len = $img[1].Length
    $b = if ($s -ge 256) { 0 } else { $s }
    $w.Write([byte]$b); $w.Write([byte]$b); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$len); $w.Write([uint32]$offset)
    $offset += $len
}
foreach ($img in $images) { $w.Write([byte[]]$img[1]) }
$w.Close()

# Optional preview: all sizes on light and dark background
if ($Preview) {
    $pv = New-Object Drawing.Bitmap 900, 420
    $g = [Drawing.Graphics]::FromImage($pv)
    $g.Clear([Drawing.Color]::FromArgb(255, 240, 240, 240))
    $g.FillRectangle((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 32, 32, 32))), 0, 280, 900, 140)
    $x = 10
    foreach ($img in $images) {
        $s = $img[0]; $bmp = $img[2]
        $g.DrawImage($bmp, $x, 10, $s, $s)
        if ($s -le 48) { $g.DrawImage($bmp, $x, 300, $s, $s) }
        $x += [Math]::Min($s, 256) + 10
    }
    $pv.Save($Preview)
}
"ok: $OutIco ($((Get-Item $OutIco).Length) bytes)"
