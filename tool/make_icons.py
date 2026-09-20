#!/usr/bin/env python3
"""Build the app icon and the bundled logo from the web platform's artwork.

The source is BMA-NFE's own `clm_plus_logo.png` -- the file its login page
serves -- so the app cannot drift from the website's branding. Re-run after
replacing the source:

    python3 tool/make_icons.py --source ../BMA-NFE/student_registration/static/images/clm_plus_logo.png

The logo is used AS DRAWN. Its blue is #1975BB, which is not the app's
navy #003366, and it is deliberately not recoloured: a brand mark is not a
palette swatch.
"""
import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit('Pillow is required: pip install pillow')

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SOURCE = os.path.join(
    HERE, '..', 'BMA-NFE', 'student_registration', 'static', 'images', 'clm_plus_logo.png')

# Legacy launcher icons: no mask is applied, so the mark may use most of the
# canvas.
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
LEGACY_MARK_WIDTH = 0.86

# Adaptive icons: the foreground is a 108dp canvas of which only the central
# 72dp is guaranteed to survive masking and parallax. The mark is 3.15 times
# wider than it is tall, so the widest it can be while staying inside a 72dp
# CIRCLE is  w where (w/2)^2 + (0.1588w)^2 = 36^2,  i.e. w ~= 68.6dp -- 0.635
# of the canvas. 0.62 leaves a little room rather than touching the edge.
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
ADAPTIVE_MARK_WIDTH = 0.62

BACKGROUND = (255, 255, 255, 255)


def ink_bbox(im, rows=None):
    """Bounding box of everything that is neither transparent nor near-white."""
    px = im.load()
    w, h = im.size
    xs, ys = [], []
    for y in (rows if rows is not None else range(h)):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 20 and (r + g + b) < 720:
                xs.append(x)
                ys.append(y)
    if not xs:
        raise SystemExit('the source image looks blank')
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def split_mark_and_tagline(im):
    """The logo is a monogram above a line of type, separated by blank rows.

    Returned as two crops: the monogram alone (for the launcher icon, where
    the tagline would be illegible at 48 px) and the whole lockup (for the
    login page, which is what the website shows there).
    """
    px = im.load()
    w, h = im.size
    counts = []
    for y in range(h):
        n = 0
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 20 and (r + g + b) < 720:
                n += 1
        counts.append(n)
    filled = [y for y, n in enumerate(counts) if n]
    top, bottom = filled[0], filled[-1]
    gaps, start = [], None
    for y in range(top, bottom + 1):
        if counts[y] == 0 and start is None:
            start = y
        elif counts[y] and start is not None:
            if y - start >= 4:
                gaps.append((start, y - 1))
            start = None
    if not gaps:
        raise SystemExit('expected a blank band between the mark and the tagline')
    # The widest band is the one separating the two blocks.
    split = max(gaps, key=lambda g: g[1] - g[0])[0]
    mark = im.crop(ink_bbox(im, rows=range(top, split)))
    whole = im.crop(ink_bbox(im))
    return mark, whole


def centred(mark, size, width_fraction, background, circle=False):
    """The mark, scaled to a fraction of the width, centred on a square."""
    target_w = max(1, int(round(size * width_fraction)))
    target_h = max(1, int(round(target_w * mark.size[1] / mark.size[0])))
    scaled = mark.resize((target_w, target_h), Image.LANCZOS)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    if background is not None:
        if circle:
            from PIL import ImageDraw
            plate = Image.new('RGBA', (size * 4, size * 4), (0, 0, 0, 0))
            ImageDraw.Draw(plate).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=background)
            canvas.alpha_composite(plate.resize((size, size), Image.LANCZOS))
        else:
            canvas.alpha_composite(Image.new('RGBA', (size, size), background))
    canvas.alpha_composite(scaled, ((size - target_w) // 2, (size - target_h) // 2))
    return canvas


def write(path, image):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path)
    print('wrote %s (%dx%d)' % (os.path.relpath(path, HERE), *image.size))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', default=DEFAULT_SOURCE)
    args = ap.parse_args()
    if not os.path.exists(args.source):
        sys.exit('source not found: %s\npoint --source at BMA-NFE clm_plus_logo.png' % args.source)

    source = Image.open(args.source).convert('RGBA')
    mark, whole = split_mark_and_tagline(source)
    print('source %s -> mark %s, lockup %s' % (source.size, mark.size, whole.size))

    write(os.path.join(HERE, 'assets', 'images', 'bma_logo.png'), whole)
    write(os.path.join(HERE, 'assets', 'images', 'bma_mark.png'), mark)

    res = os.path.join(HERE, 'android', 'app', 'src', 'main', 'res')
    for density, size in LEGACY.items():
        write(os.path.join(res, 'mipmap-%s' % density, 'ic_launcher.png'),
              centred(mark, size, LEGACY_MARK_WIDTH, BACKGROUND))
        # Pre-Android-8 launchers that mask to a circle use this one.
        write(os.path.join(res, 'mipmap-%s' % density, 'ic_launcher_round.png'),
              centred(mark, size, LEGACY_MARK_WIDTH * 0.74, BACKGROUND, circle=True))
    for density, size in ADAPTIVE.items():
        write(os.path.join(res, 'mipmap-%s' % density, 'ic_launcher_foreground.png'),
              centred(mark, size, ADAPTIVE_MARK_WIDTH, None))


if __name__ == '__main__':
    main()
