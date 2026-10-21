"""Irregular foliage cards. Silhouettes are branches and crowns, not circles."""
import math
import random
from PIL import Image, ImageDraw, ImageFilter


def leaf_poly(draw, x, y, length, width, rot, col):
    pts = []
    for s in range(12):
        side = 1 if s < 6 else -1
        u = (s if s < 6 else 11 - s) / 5.0
        belly = math.sin(u * math.pi) ** 0.9
        lx = (u * 2.0 - 1.0) * length * 0.5
        ly = side * belly * width * 0.5
        xr = lx * math.cos(rot) - ly * math.sin(rot)
        yr = lx * math.sin(rot) + ly * math.cos(rot)
        pts.append((x + xr, y + yr))
    draw.polygon(pts, fill=col)


def shade(rng, lo, hi):
    t = rng.random()
    return tuple(int(lo[i] + (hi[i] - lo[i]) * t) for i in range(3)) + (255,)


def crown(path):
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img, "RGBA")
    rng = random.Random(21)
    cx, cy = size * 0.5, size * 0.52
    for i in range(1500):
        ang = rng.random() * math.tau
        rad = rng.random() ** 0.5
        wobble = 1.0 + 0.26 * math.sin(ang * 3.0) + 0.14 * math.sin(ang * 8.0 + 1.7)
        x = cx + math.cos(ang) * 360 * rad * wobble
        y = cy + math.sin(ang) * 300 * rad * (0.82 if math.sin(ang) > 0.45 else 1.0) * wobble
        length = rng.uniform(18, 54)
        col = shade(rng, (24, 52, 20), (86, 124, 44))
        leaf_poly(draw, x, y, length, length * rng.uniform(0.3, 0.5), rng.uniform(0, math.tau), col)
    img = img.filter(ImageFilter.GaussianBlur(0.3))
    img.save(path)


def pine(path):
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img, "RGBA")
    rng = random.Random(8)
    apex = (size * 0.5, 70)
    left = (90, 940)
    right = (934, 940)
    draw.polygon([apex, left, right], fill=(18, 40, 18, 255))
    for i in range(2600):
        u = rng.random()
        v = rng.random()
        if u + v > 1.0:
            u, v = 1.0 - u, 1.0 - v
        x = apex[0] + (left[0] - apex[0]) * u + (right[0] - apex[0]) * v
        y = apex[1] + (left[1] - apex[1]) * u + (right[1] - apex[1]) * v
        heading = rng.uniform(-2.4, -0.7)
        length = rng.uniform(10, 26)
        col = shade(rng, (24, 52, 20), (78, 112, 40))
        draw.line((x, y, x + math.cos(heading) * length, y + math.sin(heading) * length), fill=col, width=rng.choice((2, 3, 3, 4)))
    for i in range(500):
        edge = rng.random()
        x = apex[0] + (right[0] - left[0]) * edge * 0.5 + (left[0] - apex[0]) * (1.0 - edge) * 0.15
        # stick needles out of the two slanted edges
        side = -1 if rng.random() < 0.5 else 1
        t = rng.random()
        if side < 0:
            x = apex[0] + (left[0] - apex[0]) * t
            y = apex[1] + (left[1] - apex[1]) * t
            ang = math.atan2(left[1] - apex[1], left[0] - apex[0]) - 1.2
        else:
            x = apex[0] + (right[0] - apex[0]) * t
            y = apex[1] + (right[1] - apex[1]) * t
            ang = math.atan2(right[1] - apex[1], right[0] - apex[0]) + 1.2
        length = rng.uniform(16, 42)
        col = shade(rng, (36, 70, 28), (96, 130, 48))
        draw.line((x, y, x + math.cos(ang) * length, y + math.sin(ang) * length), fill=col, width=3)
    img = img.filter(ImageFilter.GaussianBlur(0.4))
    img.save(path)


def scrub(path):
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img, "RGBA")
    rng = random.Random(4)
    cx, cy = size * 0.5, size * 0.72
    for i in range(720):
        ang = rng.uniform(math.pi + 0.35, math.tau - 0.35)
        rad = rng.random() ** 0.5
        wobble = 1.0 + 0.2 * math.sin(ang * 4.0 + 1.0)
        x = cx + math.cos(ang) * 420 * rad * wobble
        y = cy + math.sin(ang) * 280 * rad * wobble
        length = rng.uniform(18, 52)
        col = shade(rng, (62, 70, 32), (118, 112, 52))
        leaf_poly(draw, x, y, length, length * rng.uniform(0.22, 0.4), rng.uniform(-0.8, 0.8) - math.pi / 2, col)
    img = img.filter(ImageFilter.GaussianBlur(0.35))
    img.save(path)


def twig(path):
    size = 512
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img, "RGBA")
    rng = random.Random(15)
    heading = -math.pi / 2 + rng.uniform(-0.3, 0.3)
    for i in range(160):
        t = rng.random() ** 0.65
        along = t * 200
        side = rng.gauss(0, 28 + t * 50)
        x = size * 0.5 + math.cos(heading) * along + math.cos(heading + math.pi / 2) * side
        y = size * 0.78 + math.sin(heading) * along + math.sin(heading + math.pi / 2) * side
        length = rng.uniform(16, 40)
        col = shade(rng, (30, 62, 24), (100, 132, 50))
        leaf_poly(draw, x, y, length, length * 0.36, heading + rng.uniform(-1.2, 1.2), col)
    img = img.filter(ImageFilter.GaussianBlur(0.3))
    img.save(path)


def grass(path):
    w, h = 256, 512
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img, "RGBA")
    rng = random.Random(5)
    for b in range(9):
        x = 16 + b * 26
        lean = rng.uniform(-36, 36)
        height = rng.randint(280, 470)
        half = rng.uniform(8, 13)
        root = (rng.randint(96, 118), rng.randint(82, 98), rng.randint(48, 62), 255)
        tip = (rng.randint(138, 160), rng.randint(118, 136), rng.randint(68, 84), 255)
        pts_l = []
        pts_r = []
        steps = 22
        for s in range(steps):
            t = s / (steps - 1)
            y = h - 1 - t * height
            xm = x + lean * t * t
            hw = half * (1.0 - t * 0.85)
            pts_l.append((xm - hw, y))
            pts_r.append((xm + hw, y))
        mid = tuple(int((root[i] + tip[i]) * 0.5) for i in range(4))
        draw.polygon(pts_l + list(reversed(pts_r)), fill=mid)
    img = img.filter(ImageFilter.GaussianBlur(0.35))
    img.save(path)


if __name__ == "__main__":
    root = r"C:\Games\AshenCounty2\assets\foliage"
    crown(root + r"\leaf_cards.png")
    pine(root + r"\pine_cards.png")
    scrub(root + r"\scrub_cards.png")
    twig(root + r"\twig_cards.png")
    grass(root + r"\grass_blade.png")
    print("ok")
