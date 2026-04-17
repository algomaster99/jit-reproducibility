#!/usr/bin/env python3
"""
Visualise a merged AOT cache as two stacked horizontal bar charts:
  Row 1 — full tree.aot split into JDK / App/Library / Hidden
  Row 2 — App/Library only, broken down by contributing sub-cache

Also writes .classes list files for every bucket:
  tree-jdk.classes
  tree-app.classes
  tree-hidden.classes
  tree-other.classes
  tree-app-<label>.classes   (one per sub-cache, App/Library classes only)
  tree-app-unknown.classes   (App/Library classes not in any sub-cache)

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
    print(f"  wrote {len(classes):>5} classes → {path}")

def main():
    parser = argparse.ArgumentParser(description="Generate AOT cache breakdown chart")
    parser.add_argument("--output-dir", "-o", default=None,
                        help="Directory for output files (default: directory of tree.classes)")
    parser.add_argument("tree_classes", help="Path to tree.classes file")
    parser.add_argument("sub_caches", nargs="+", metavar="path.classes:Label",
                        help="Sub-cache class lists with labels")
    args = parser.parse_args()

    tree_classes = load_classes(args.tree_classes)
    out_dir      = args.output_dir if args.output_dir else os.path.dirname(os.path.abspath(args.tree_classes))
    os.makedirs(out_dir, exist_ok=True)
    output_pdf   = os.path.join(out_dir, "viz.pdf")

    subs = []
    for arg in args.sub_caches:
        if ":" not in arg:
            print(f"Expected <path.classes:Label>, got: {arg}", file=sys.stderr)
            sys.exit(1)
        path, label = arg.rsplit(":", 1)
        if not os.path.isfile(path):
            print(f"File not found: {path!r}  (from arg: {arg!r})", file=sys.stderr)
            print("Tip: arguments may have been joined by copy-paste — check for missing spaces.", file=sys.stderr)
            sys.exit(1)
        subs.append((label, set(load_classes(path))))

    # ── Classify ──────────────────────────────────────────────────────────────
    buckets   = {"JDK": [], "App/Library": [], "Hidden": [], "Other": []}
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

    # ── Write list files ──────────────────────────────────────────────────────
    print("\nWriting list files:")
    write_list(os.path.join(out_dir, "tree-jdk.classes"),    buckets["JDK"])
    write_list(os.path.join(out_dir, "tree-app.classes"),    buckets["App/Library"])
    write_list(os.path.join(out_dir, "tree-hidden.classes"), buckets["Hidden"])
    write_list(os.path.join(out_dir, "tree-other.classes"),  buckets["Other"])
    for label in sub_labels:
        write_list(os.path.join(out_dir, f"tree-app-{label}.classes"), app_sub[label])
    write_list(os.path.join(out_dir, "tree-app-unknown.classes"), app_unknown)

    # ── Report zeros ──────────────────────────────────────────────────────────
    zeros  = [c for c in ["JDK", "App/Library", "Hidden", "Other"] if not buckets[c]]
    zeros += [lb for lb in sub_labels if not app_sub[lb]]
    if zeros:
        print(f"\nSkipped (0 classes): {', '.join(zeros)}")

    # ── Render ────────────────────────────────────────────────────────────────
    _render_stacked_bars(buckets, app_sub, app_unknown, sub_labels, output_pdf)


def _render_stacked_bars(buckets, app_sub, app_unknown, sub_labels, output_path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches

    total     = sum(len(v) for v in buckets.values())
    app_total = len(buckets["App/Library"])

    # ── Segment definitions ───────────────────────────────────────────────────
    top_segs = [
        ("JDK",         len(buckets["JDK"]),  "#4C8CBF"),
        ("App/Library", app_total,             "#6AAB5E"),
        ("Hidden",      len(buckets["Hidden"]),"#E07B3A"),
    ]
    top_segs = [(n, v, c) for n, v, c in top_segs if v > 0]

    COLORS  = plt.cm.tab20.colors
    sub_raw = [(lb, len(app_sub[lb])) for lb in sub_labels]
    sub_raw.append(("Unknown", len(app_unknown)))
    sub_raw = [(n, v) for n, v in sub_raw if v > 0]
    sub_raw.sort(key=lambda x: -x[1])
    sub_segs = [(n, v, COLORS[i % len(COLORS)]) for i, (n, v) in enumerate(sub_raw)]

    # ── Figure ────────────────────────────────────────────────────────────────
    fig, (ax1, ax2) = plt.subplots(
        2, 1, figsize=(11, 4.0),
        gridspec_kw={"height_ratios": [1, 1], "hspace": 0.7},
    )
    fig.patch.set_facecolor("white")

    def draw_bar(ax, segs, bar_total, title):
        ax.set_xlim(0, bar_total)
        ax.set_ylim(-0.7, 1.0)
        ax.axis("off")
        ax.set_title(title, fontsize=8.5, loc="left", pad=3,
                     color="#444444", fontweight="bold")

        BAR_Y          = 0.0
        BAR_H          = 0.65
        THRESH_WIDE    = 0.08    # fraction → full two-line label inside
        THRESH_MEDIUM  = 0.025   # fraction → compact one-line label inside

        x = 0
        ext_labels = []

        for name, val, color in segs:
            rect = mpatches.FancyBboxPatch(
                (x, BAR_Y), val, BAR_H,
                boxstyle="square,pad=0",
                facecolor=color, edgecolor="white", linewidth=0.8,
            )
            ax.add_patch(rect)

            frac = val / bar_total
            cx   = x + val / 2
            cy   = BAR_Y + BAR_H / 2

            if frac >= THRESH_WIDE:
                ax.text(cx, cy + 0.10, name,
                        ha="center", va="center", fontsize=8,
                        fontweight="bold", color="white")
                ax.text(cx, cy - 0.13, f"{val:,}  ({frac*100:.1f}%)",
                        ha="center", va="center", fontsize=7, color="white")
            elif frac >= THRESH_MEDIUM:
                ax.text(cx, cy + 0.07, name,
                        ha="center", va="center", fontsize=6.5,
                        fontweight="bold", color="white")
                ax.text(cx, cy - 0.12, f"{val:,}",
                        ha="center", va="center", fontsize=6, color="white")
            else:
                ext_labels.append((x + val / 2, name, val, color))

            x += val

        # External labels — fan out with arrows so they don't overlap
        if ext_labels:
            n = len(ext_labels)
            label_y = BAR_Y - 0.42
            # Spread label anchors across the full bar width
            spread_lo = bar_total * 0.10
            spread_hi = bar_total * 0.95
            positions = [spread_lo + (spread_hi - spread_lo) * i / max(n - 1, 1)
                         for i in range(n)]
            for i, (cx, name, val, color) in enumerate(ext_labels):
                ax.annotate(
                    f"{name}  {val:,}",
                    xy=(cx, BAR_Y),
                    xytext=(positions[i], label_y),
                    ha="center", va="top",
                    fontsize=6, color="#333",
                    annotation_clip=False,
                    arrowprops=dict(
                        arrowstyle="-|>",
                        color="#aaa",
                        lw=0.7,
                        mutation_scale=6,
                    ),
                )

    draw_bar(ax1, top_segs, total,
             f"tree.aot — {total:,} classes total")
    draw_bar(ax2, sub_segs, app_total,
             f"App/Library — {app_total:,} classes  (first-match sub-cache attribution)")

    plt.savefig(output_path, format="pdf", bbox_inches="tight", dpi=150)
    plt.close()
    print(f"Chart written to {output_path}")


if __name__ == "__main__":
    main()
