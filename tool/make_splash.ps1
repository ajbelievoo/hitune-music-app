Add-Type -AssemblyName System.Drawing

$W = 720
$H = 1100
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.InterpolationMode = 'HighQualityBicubic'
$g.TextRenderingHint = 'AntiAlias'
$g.Clear([System.Drawing.Color]::Transparent)

# Gradient rounded box (logo card)
$box = 280
$bx = [float](($W - $box) / 2)
$by = [float]150
$r = 72
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc($bx, $by, $r * 2, $r * 2, 180, 90)
$path.AddArc($bx + $box - $r * 2, $by, $r * 2, $r * 2, 270, 90)
$path.AddArc($bx + $box - $r * 2, $by + $box - $r * 2, $r * 2, $r * 2, 0, 90)
$path.AddArc($bx, $by + $box - $r * 2, $r * 2, $r * 2, 90, 90)
$path.CloseFigure()

$cyan = [System.Drawing.Color]::FromArgb(255, 15, 168, 212)
$pink = [System.Drawing.Color]::FromArgb(255, 229, 107, 216)
$pt1 = New-Object System.Drawing.PointF -ArgumentList ([float]$bx), ([float]$by)
$pt2 = New-Object System.Drawing.PointF -ArgumentList ([float]($bx + $box)), ([float]($by + $box))
$lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList $pt1, $pt2, $cyan, $pink
$g.FillPath($lg, $path)

# Logo inside the box
$logo = [System.Drawing.Image]::FromFile('E:\hitune_music\assets\logo.png')
$pad = 40
$lw = $box - $pad * 2
$lh = [int]($logo.Height * $lw / $logo.Width)
$g.DrawImage($logo, $bx + $pad, $by + ($box - $lh) / 2, $lw, $lh)

# Title + tagline
$f1 = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', ([float]52), ([System.Drawing.FontStyle]::Bold)
$f2 = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', ([float]30), ([System.Drawing.FontStyle]::Regular)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = 'Center'
$dark = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(255, 28, 28, 30))
$gray = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(255, 142, 142, 147))
$rect1 = New-Object System.Drawing.RectangleF -ArgumentList ([float]0), ([float]($by + $box + 70)), ([float]$W), ([float]100)
$rect2 = New-Object System.Drawing.RectangleF -ArgumentList ([float]0), ([float]($by + $box + 185)), ([float]$W), ([float]70)
$g.DrawString('HiTune Music', $f1, $dark, $rect1, $sf)
$g.DrawString('Your music, your way', $f2, $gray, $rect2, $sf)

$bmp.Save('E:\hitune_music\android\app\src\main\res\drawable\launch_logo.png', [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
$logo.Dispose()
Write-Output 'launch_logo.png written'
