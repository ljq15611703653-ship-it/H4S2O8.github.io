"""Build the redistributable CJK font subset used by the Web export."""

from __future__ import annotations

from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont


PROJECT = Path(__file__).resolve().parents[1]
SOURCE_FONT = Path(r"C:\Windows\Fonts\NotoSansSC-VF.ttf")
OUTPUT_FONT = PROJECT / "assets" / "fonts" / "NotoSansSC-MaxwellSubset.ttf"


def collect_characters() -> str:
    characters = set(chr(codepoint) for codepoint in range(0x20, 0x7F))
    for pattern in ("*.gd", "*.tscn", "*.tres", "*.md", "project.godot"):
        for path in PROJECT.rglob(pattern):
            if ".godot" not in path.parts:
                characters.update(path.read_text(encoding="utf-8"))
    characters.update("—·→−×℃（）【】《》“”‘’…，。；：！？、")
    return "".join(sorted(characters))


def main() -> None:
    if not SOURCE_FONT.exists():
        raise SystemExit(f"Missing local open-source Noto font: {SOURCE_FONT}")
    options = subset.Options()
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    options.name_legacy = True
    options.layout_features = ["*"]
    options.recalc_average_width = True
    options.recalc_max_context = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    font = TTFont(SOURCE_FONT)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=collect_characters())
    subsetter.subset(font)
    OUTPUT_FONT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUTPUT_FONT)
    print(f"Wrote {OUTPUT_FONT} ({OUTPUT_FONT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
