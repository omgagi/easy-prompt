"""Render the Easy Prompt app icon at 1024 x 1024."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SCALE = 3
SIZE = 1024
canvas_size = SIZE * SCALE

def box(values):
    return tuple(round(value * SCALE) for value in values)

background = Image.new("RGB", (canvas_size, canvas_size), (9, 28, 49))
glow = Image.new("RGBA", background.size, (0, 0, 0, 0))
glow_draw = ImageDraw.Draw(glow)
glow_draw.ellipse(box((24, -220, 1000, 756)), fill=(32, 112, 145, 135))
glow = glow.filter(ImageFilter.GaussianBlur(155 * SCALE))
background = Image.alpha_composite(background.convert("RGBA"), glow)

shadow = Image.new("RGBA", background.size, (0, 0, 0, 0))
shadow_draw = ImageDraw.Draw(shadow)
shadow_draw.rounded_rectangle(box((229, 203, 811, 860)), radius=145 * SCALE, fill=(0, 8, 22, 180))
shadow = shadow.filter(ImageFilter.GaussianBlur(40 * SCALE))
background = Image.alpha_composite(background, shadow)

draw = ImageDraw.Draw(background)
draw.rounded_rectangle(box((210, 174, 814, 834)), radius=145 * SCALE, fill=(250, 247, 239, 255))
draw.ellipse(box((440, 242, 584, 386)), fill=(18, 45, 67, 255))
draw.ellipse(box((478, 280, 546, 348)), fill=(248, 185, 67, 255))

draw.rounded_rectangle(box((300, 445, 725, 486)), radius=20 * SCALE, fill=(25, 58, 78, 255))
draw.rounded_rectangle(box((300, 549, 745, 613)), radius=32 * SCALE, fill=(247, 181, 60, 255))
draw.rounded_rectangle(box((300, 677, 634, 718)), radius=20 * SCALE, fill=(25, 58, 78, 255))

output = Path(__file__).resolve().parents[1] / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
background.convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(output, optimize=True)
print(output)
