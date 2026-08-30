"""Derive elevator_screen.gdshader's screen_rect from the plate texture.

The rect names the inner glass, and it has to hide every baked pixel of the
concept render's readout without eating the bezel's inner highlight. The boundary
that does that is the bevel shadow -- the darkest gutter between the lip and the
glass -- so this finds the luminance minimum on each side rather than asking
anyone to drag a slider. Re-run it whenever the plate is re-exported.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

PLATE = (
    Path(__file__).resolve().parents[4]
    / "assets/art/environment/elevator_car/screen/t_elevator_screen_plate.png"
)

# Search windows, in plate pixels. Wide enough to survive a re-export that shifts
# the bezel a little, narrow enough that the hazard stripes cannot win the minimum.
SEARCH = {"left": (60, 300), "right": (1250, 1470), "top": (40, 260), "bottom": (760, 1000)}


def main() -> int:
    image = Image.open(PLATE).convert("RGB")
    width, height = image.size
    blurred = np.asarray(image.convert("L").filter(ImageFilter.GaussianBlur(9)), dtype=float)

    columns = blurred[250:800, :].mean(axis=0)
    rows = blurred[:, 300:1200].mean(axis=1)

    left = SEARCH["left"][0] + int(np.argmin(columns[slice(*SEARCH["left"])]))
    right = SEARCH["right"][0] + int(np.argmin(columns[slice(*SEARCH["right"])]))
    top = SEARCH["top"][0] + int(np.argmin(rows[slice(*SEARCH["top"])]))
    bottom = SEARCH["bottom"][0] + int(np.argmin(rows[slice(*SEARCH["bottom"])]))

    rect = (left / width, top / height, (right - left) / width, (bottom - top) / height)

    print(f"plate      {width} x {height}")
    print(f"glass px   x {left}..{right}  y {top}..{bottom}")
    print(f"glass size {right - left} x {bottom - top}  aspect {(right - left) / (bottom - top):.4f}")
    print("screen_rect = vec4({:.6f}, {:.6f}, {:.6f}, {:.6f})".format(*rect))

    # The baked readout must fall inside the rect. Only the glass is checked: the
    # bezel's hazard stripes are legitimately bright and would fail a whole-image
    # version of this test.
    glass = np.asarray(image, dtype=float)[top:bottom, left:right] / 255.0
    luma = glass @ np.array([0.2126, 0.7152, 0.0722])
    ys, xs = np.where(luma > 0.25)
    print(f"baked content inside glass: x {xs.min()}..{xs.max()}  y {ys.min()}..{ys.max()}")
    margin = min(xs.min(), ys.min(), (right - left) - xs.max(), (bottom - top) - ys.max())
    print(f"tightest margin to the rect edge: {margin} px")
    return 0 if margin > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
