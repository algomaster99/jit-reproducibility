#!/usr/bin/env python3
"""
Generate a LaTeX/TikZ two-level treemap and .classes list files for an AOT cache.

Fixed outer layout (matches the target figure):
  Left column  : JDK  (full height, width proportional to class count)
  Right column : Hidden (top strip) / App/Library (large bottom block)
  Inside App   : squarified sub-tiles per contributing sub-cache

Output files written to --output-dir:
  tree-jdk.classes, tree-app.classes, tree-hidden.classes, tree-other.classes
  tree-app-<label>.classes  (one per sub-cache)
  tree-app-unknown.classes
  viz.tex   (TikZ snippet, input-able or paste-able into a paper)

Usage:
  python3 viz.py [--output-dir DIR] <tree.classes> <path.classes:Label> [...]
"""

import sys
import os
import argparse

JDK_PREFIXES = (
    "java/", "javax/", "sun/", "jdk/",
    "com/sun/", "com/oracle/", "org/xml/",
    "org/w3c/", "org/ietf/", "org/omg/",
)

TAB20 = [
    (31, 119, 180), (255, 127, 14),  (44, 160, 44),  (214,  39,  40),
    (148, 103, 189),(140,  86,  75), (227, 119, 194), (127, 127, 127),
    (188, 189,  34), (23, 190, 207), (174, 199, 232), (255, 187, 120),
    (152, 223, 138), (255, 152, 150), (197, 176, 213), (196, 156, 148),
    (247, 182, 210), (199, 199, 199), (219, 219, 141), (158, 218, 229),
]

SEG_COLORS = {
    "JDK":         ("jdkcolor",    "76,140,191"),
    "App/Library": ("appcolor",    "106,171,94"),
    "Hidden":      ("hiddencolor", "224,123,58"),
    "Other":       ("othercolor",  "160,160,160"),
}


def classify(cls):
    base = cls
    if base.startswith("["):
        base = base.lstrip("[")
        if base.startswith("L") and base.endswith(";"):
            base = base[1:-1]
    if any(base.startswith(p) for p in JDK_PREFIXES):
        return "JDK"
    if "/0x" in cls or "+0x" in cls:
        return "Hidden"
    if "$$Lambda" in cls:
        return "Other"
    return "App/Library"


def load_classes(path):
    with open(path) as f:
        return [line.rstrip("\n") for line in f if line.strip()]


def write_list(path, classes):
    with open(path, "w") as f:
        for c in sorted(classes):
            f.write(c + "\n")
    print(f"  wrote {len(classes):>5} classes -> {path}")


def safe_cname(name):
    return "vizSub" + "".join(c for c in name.lower() if c.isalnum())


# ── Squarified treemap (used for App/Library sub-tiles) ───────────────────────

def _worst(row_areas, w):
    s = sum(row_areas)
    if s == 0:
        return float("inf")
    return max(max(w * w * a / (s * s), s * s / (w * w * a))
               for a in row_areas if a > 0)


def _layout_row(names, row_areas, x, y, width, height, result):
    if width >= height:
        strip_h = sum(row_areas) / width
        rx = x
        for name, area in zip(names, row_areas):
            rw = area / strip_h if strip_h > 0 else 0
            result.append((name, rx, y, rw, strip_h))
            rx += rw
    else:
        strip_w = sum(row_areas) / height
        ry = y
        for name, area in zip(names, row_areas):
            rh = area / strip_w if strip_w > 0 else 0
            result.append((name, x, ry, strip_w, rh))
            ry += rh


def _squarify(items_area, x, y, width, height, result):
    if not items_area:
        return
    if len(items_area) == 1:
        result.append((items_area[0][0], x, y, width, height))
        return

    w = min(width, height)
    row_names, row_areas, row_sum = [], [], 0.0

    for i, (name, area) in enumerate(items_area):
        candidate = row_areas + [area]
        if not row_areas or _worst(candidate, w) <= _worst(row_areas, w):
            row_names.append(name)
            row_areas.append(area)
            row_sum += area
        else:
            _layout_row(row_names, row_areas, x, y, width, height, result)
            if width >= height:
                strip_h = row_sum / width
                _squarify(items_area[i:], x, y + strip_h, width, height - strip_h, result)
            else:
                strip_w = row_sum / height
                _squarify(items_area[i:], x + strip_w, y, width - strip_w, height, result)
            return

    _layout_row(row_names, row_areas, x, y, width, height, result)


def squarify(items, x, y, width, height):
    """items: [(name, value)] sorted descending. Returns [(name, x, y, w, h)]."""
    items = sorted(items, key=lambda v: -v[1])
    total = sum(v for _, v in items)
    if total == 0:
        return []
    scaled = [(n, v / total * width * height) for n, v in items]
    result = []
    _squarify(scaled, x, y, width, height, result)
    return result


# ── Horizontal strip layout with minimum height ───────────────────────────────

def _horiz_strips(items, x, y, w, h):
    """
    Lay items out as horizontal strips (full width, stacked top→bottom).
    Items smaller than MIN_SUB_H get that minimum height; larger items share the
    remaining space proportionally so the total stays exactly h.
    Returns [(name, val, x, y, w, h)].
    """
    n_gaps   = max(len(items) - 1, 0)
    avail_h  = h - n_gaps * SUB_GAP

    # Split into items that need a minimum floor vs. those that don't
    total_v   = sum(v for _, v in items)
    natural   = {n: avail_h * v / total_v for n, v in items}
    small     = [(n, v) for n, v in items if natural[n] < MIN_SUB_H]
    large     = [(n, v) for n, v in items if natural[n] >= MIN_SUB_H]

    min_used  = len(small) * MIN_SUB_H
    large_h   = avail_h - min_used
    large_v   = sum(v for _, v in large)

    heights = {}
    for n, v in items:
        if natural[n] < MIN_SUB_H:
            heights[n] = MIN_SUB_H
        else:
            heights[n] = large_h * v / large_v if large_v > 0 else 0

    result = []
    cur_y = y + h   # start from top, work downwards
    for n, v in items:
        sh = heights[n]
        result.append((n, v, x, cur_y - sh, w, sh))
        cur_y -= sh + SUB_GAP
    return result


# ── TikZ rendering ────────────────────────────────────────────────────────────

BORDER    = 1.0   # outer border padding (mm)
INNER     = 0.8   # padding inside App tile before sub-tiles (mm)
MIN_H     = 7.0   # minimum height for outer tiles (mm)
MIN_SUB_H = 4.0   # minimum height for sub-cache strips (mm)
SUB_GAP   = 0.5   # gap between sub-cache strips (mm)


def _tile(L, x, y, w, h, fill, border_color="white", lw="0.8pt"):
    L.append(f"\\fill[{fill}] ({x:.3f}mm,{y:.3f}mm) rectangle ({x+w:.3f}mm,{y+h:.3f}mm);")
    L.append(f"\\draw[{border_color},line width={lw}] "
             f"({x:.3f}mm,{y:.3f}mm) rectangle ({x+w:.3f}mm,{y+h:.3f}mm);")


def _label(L, cx, cy, tw, th, text, bold=True, color="white"):
    weight = "\\bfseries" if bold else ""
    parts  = text.split("\\\\")
    name   = parts[0]
    if th >= 8 and tw >= 12:
        L.append(f"\\node[align=center,font=\\scriptsize{weight},{color}]"
                 f" at ({cx:.3f}mm,{cy:.3f}mm) {{{text}}};")
    elif th >= 5 and tw >= 7:
        L.append(f"\\node[align=center,font=\\tiny{weight},{color}]"
                 f" at ({cx:.3f}mm,{cy:.3f}mm) {{\\tiny {name}}};")
    elif th >= 3 and tw >= 10:
        # Short but wide horizontal strip — show name in tiny font
        detail = f" {parts[1]}" if len(parts) > 1 else ""
        L.append(f"\\node[align=center,font=\\tiny,{color}]"
                 f" at ({cx:.3f}mm,{cy:.3f}mm) {{\\tiny {name}{detail}}};")


def render_treemap_latex(buckets, app_sub, app_unknown, sub_labels, output_path,
                         W=130.0, H=80.0):
    total      = sum(len(v) for v in buckets.values())
    jdk_n      = len(buckets["JDK"])
    app_n      = len(buckets["App/Library"])
    hidden_n   = len(buckets["Hidden"])

    # Inner drawing area
    ix, iy    = BORDER, BORDER
    iw, ih    = W - 2*BORDER, H - 2*BORDER

    # Left column: JDK  (width proportional to class count)
    jdk_w     = iw * jdk_n / total
    right_x   = ix + jdk_w
    right_w   = iw - jdk_w

    # Right column split: Hidden (top) / App (bottom)
    right_n   = hidden_n + app_n
    if right_n > 0:
        hidden_h_nat = ih * hidden_n / right_n
        hidden_h     = max(hidden_h_nat, MIN_H) if hidden_n > 0 else 0
    else:
        hidden_h = 0
    app_h     = ih - hidden_h

    # Sub-cache layout inside App tile — horizontal strips, sorted large→small
    sub_items = [(lb, len(app_sub[lb])) for lb in sub_labels]
    sub_items.append(("Unknown", len(app_unknown)))
    sub_items = [(n, v) for n, v in sub_items if v > 0]
    sub_items.sort(key=lambda x: -x[1])
    sub_layout = _horiz_strips(sub_items, right_x + INNER, iy + INNER,
                               right_w - 2*INNER, app_h - 2*INNER)

    L = []
    emit = L.append

    # ── Color definitions ──────────────────────────────────────────────────────
    emit("% AOT treemap — color definitions")
    for cname, rgb in SEG_COLORS.values():
        emit(f"\\providecolor{{{cname}}}{{RGB}}{{{rgb}}}")
    for i, (name, _) in enumerate(sub_items):
        r, g, b = TAB20[i % len(TAB20)]
        emit(f"\\providecolor{{{safe_cname(name)}}}{{RGB}}{{{r},{g},{b}}}")
    emit("")

    emit(r"\begin{tikzpicture}")
    emit("")

    # ── Outer border ──────────────────────────────────────────────────────────
    emit("% outer border")
    emit(f"\\draw[black,line width=1pt] (0,0) rectangle ({W:.1f}mm,{H:.1f}mm);")
    emit(f"\\node[above right,font=\\small\\bfseries] at (0,{H:.1f}mm) {{tree.aot}};")
    emit(f"\\node[below right,font=\\scriptsize,gray] at (0,0mm) {{{total:,} classes}};")
    emit("")

    # ── JDK tile ──────────────────────────────────────────────────────────────
    emit("% JDK")
    _tile(L, ix, iy, jdk_w, ih, "jdkcolor!70")
    pct = 100.0 * jdk_n / total
    _label(L, ix + jdk_w/2, iy + ih/2, jdk_w, ih,
           f"JDK\\\\{jdk_n:,} ({pct:.1f}\\%)")

    # ── Hidden tile ────────────────────────────────────────────────────────────
    if hidden_n > 0:
        emit("% Hidden")
        _tile(L, right_x, iy + app_h, right_w, hidden_h, "hiddencolor!70")
        pct = 100.0 * hidden_n / total
        _label(L, right_x + right_w/2, iy + app_h + hidden_h/2, right_w, hidden_h,
               f"Hidden\\\\{hidden_n:,} ({pct:.1f}\\%)")

    # ── App/Library tile (background) ─────────────────────────────────────────
    emit("% App/Library background")
    _tile(L, right_x, iy, right_w, app_h, "appcolor!20", border_color="black!30")
    pct = 100.0 * app_n / total
    # Title in the corner of the App tile
    emit(f"\\node[above right,font=\\tiny\\bfseries,appcolor!80!black] "
         f"at ({right_x:.3f}mm,{iy:.3f}mm) {{App/Library  {app_n:,} ({pct:.1f}\\%)}};")

    # ── App sub-tiles ──────────────────────────────────────────────────────────
    emit("% App/Library sub-tiles")
    for name, val, tx, ty, tw, th in sub_layout:
        cname = safe_cname(name)
        pct   = 100.0 * val / app_n
        _tile(L, tx, ty, tw, th, cname, border_color="white", lw="0.5pt")
        _label(L, tx + tw/2, ty + th/2, tw, th,
               f"{name}\\\\{val:,} ({pct:.1f}\\%)")

    emit("")
    emit(r"\end{tikzpicture}")

    with open(output_path, "w") as f:
        f.write("\n".join(L) + "\n")
    print(f"LaTeX treemap written to {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate AOT cache breakdown (LaTeX treemap + .classes lists)")
    parser.add_argument("--output-dir", "-o", default=None)
    parser.add_argument("tree_classes")
    parser.add_argument("sub_caches", nargs="+", metavar="path.classes:Label")
    args = parser.parse_args()

    tree_classes = load_classes(args.tree_classes)
    out_dir      = args.output_dir or os.path.dirname(os.path.abspath(args.tree_classes))
    os.makedirs(out_dir, exist_ok=True)
    output_tex   = os.path.join(out_dir, "viz.tex")

    subs = []
    for arg in args.sub_caches:
        if ":" not in arg:
            print(f"Expected <path.classes:Label>, got: {arg}", file=sys.stderr)
            sys.exit(1)
        path, label = arg.rsplit(":", 1)
        if not os.path.isfile(path):
            print(f"File not found: {path!r}", file=sys.stderr)
            sys.exit(1)
        subs.append((label, set(load_classes(path))))

    buckets     = {"JDK": [], "App/Library": [], "Hidden": [], "Other": []}
    for cls in tree_classes:
        buckets[classify(cls)].append(cls)

    sub_labels  = [label for label, _ in subs]
    app_sub     = {label: [] for label in sub_labels}
    app_unknown = []
    for cls in buckets["App/Library"]:
        assigned = next((lb for lb, s in subs if cls in s), None)
        if assigned:
            app_sub[assigned].append(cls)
        else:
            app_unknown.append(cls)

    print("\nWriting list files:")
    write_list(os.path.join(out_dir, "tree-jdk.classes"),    buckets["JDK"])
    write_list(os.path.join(out_dir, "tree-app.classes"),    buckets["App/Library"])
    write_list(os.path.join(out_dir, "tree-hidden.classes"), buckets["Hidden"])
    write_list(os.path.join(out_dir, "tree-other.classes"),  buckets["Other"])
    for label in sub_labels:
        write_list(os.path.join(out_dir, f"tree-app-{label}.classes"), app_sub[label])
    write_list(os.path.join(out_dir, "tree-app-unknown.classes"), app_unknown)

    zeros  = [c for c in ["JDK", "App/Library", "Hidden", "Other"] if not buckets[c]]
    zeros += [lb for lb in sub_labels if not app_sub[lb]]
    if zeros:
        print(f"\nSkipped (0 classes): {', '.join(zeros)}")

    print()
    render_treemap_latex(buckets, app_sub, app_unknown, sub_labels, output_tex)


if __name__ == "__main__":
    main()
