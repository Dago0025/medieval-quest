# Icona del Culto Imperiale dal simbolo scelto da Federico (I con tre barre, nero su bianco), resa in oro: 144x160 come le
# icone rifatte (8x 18x20). Uso: python prepara_icona_culto.py <simbolo.png> <uscita.png>
import sys
from PIL import Image, ImageFilter, ImageChops
W, H, S = 144, 160, 4
src = Image.open(sys.argv[1]).convert("L")
mask = src.point(lambda v: 255 if v < 128 else 0)          # forma nera
mask = src.point(lambda v: max(0, min(255, int((200 - v) * 255 / 120))))  # bordi morbidi
box = mask.point(lambda v: 255 if v > 128 else 0).getbbox()
shape = mask.crop(box)
scale = min((W * S * 0.80) / shape.width, (H * S * 0.86) / shape.height)
shape = shape.resize((max(1, int(shape.width * scale)), max(1, int(shape.height * scale))), Image.LANCZOS)
full = Image.new("L", (W * S, H * S), 0)
full.paste(shape, ((W * S - shape.width) // 2, (H * S - shape.height) // 2))
grad = Image.new("RGBA", (W * S, H * S))
gp = grad.load()
top, mid, bot = (255, 238, 156), (232, 182, 58), (150, 98, 22)
for yy in range(H * S):
    t = yy / (H * S - 1)
    if t < 0.45:
        k = t / 0.45; c = tuple(int(top[i] + (mid[i] - top[i]) * k) for i in range(3))
    else:
        k = (t - 0.45) / 0.55; c = tuple(int(mid[i] + (bot[i] - mid[i]) * k) for i in range(3))
    for xx in range(W * S):
        gp[xx, yy] = c + (255,)
outline = full.filter(ImageFilter.MaxFilter(4 * S + 1))
shadow = outline.filter(ImageFilter.GaussianBlur(3 * S))
out = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
sh = Image.new("RGBA", (W * S, H * S), (40, 22, 5, 0)); sh.putalpha(shadow.point(lambda v: int(v * 0.55)))
out = Image.alpha_composite(out, sh)
ol = Image.new("RGBA", (W * S, H * S), (70, 40, 8, 0)); ol.putalpha(outline)
out = Image.alpha_composite(out, ol)
gold = grad.copy(); gold.putalpha(full)
out = Image.alpha_composite(out, gold)
inner = ImageChops.subtract(full, full.transform(full.size, Image.AFFINE, (1, 0, 1.5 * S, 0, 1, 1.5 * S)))
hl = Image.new("RGBA", (W * S, H * S), (255, 250, 210, 0)); hl.putalpha(inner.point(lambda v: int(v * 0.7)))
out = Image.alpha_composite(out, hl)
out.resize((W, H), Image.LANCZOS).save(sys.argv[2])
