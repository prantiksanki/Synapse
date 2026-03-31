"""
extract_sign_images.py
======================
Extracts embedded sign-language images from the Excel workbook
"Sign Language (Prepared By Prantik).xlsx" and saves them as
individual PNG files ready to be bundled in the Flutter app.

Run once from the repo root:
    pip install pillow
    python App2/scripts/extract_sign_images.py

Output
------
  App2/assets/sign_images/<CHAR>.png   — one file per sign character
  App2/assets/sign_images/manifest.json — {"A": "A.png", ...}
"""

import zipfile
import json
import re
import os
import shutil
from pathlib import Path
from io import BytesIO

try:
    from PIL import Image
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False
    print("[WARN] Pillow not installed — images will be saved as-is (original format).")
    print("       Run: pip install pillow   to get PNG conversion.")

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR   = Path(__file__).resolve().parent
ASSETS_DIR   = SCRIPT_DIR.parent / "assets"
EXCEL_PATH   = ASSETS_DIR / "Sign Language (Prepared By Prantik).xlsx"
OUT_DIR      = ASSETS_DIR / "sign_images"
MANIFEST_OUT = OUT_DIR / "manifest.json"

# ---------------------------------------------------------------------------
# XML namespaces used inside .xlsx
# ---------------------------------------------------------------------------
NS = {
    "ss":  "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r":   "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "xdr": "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing",
    "a":   "http://schemas.openxmlformats.org/drawingml/2006/main",
    "p":   "http://schemas.openxmlformats.org/drawingml/2006/picture",
}

def strip_ns(tag: str) -> str:
    """Remove XML namespace prefix from a tag."""
    return re.sub(r"\{[^}]+\}", "", tag)


def parse_shared_strings(z: zipfile.ZipFile) -> list[str]:
    """Load xl/sharedStrings.xml and return a list of string values by index."""
    import xml.etree.ElementTree as ET
    ss_path = "xl/sharedStrings.xml"
    if ss_path not in z.namelist():
        return []
    root = ET.fromstring(z.read(ss_path))
    ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    result = []
    for si in root:
        # Concatenate all <t> text nodes within the <si> element
        text = "".join(
            t.text or "" for t in si.iter(f"{{{ns}}}t")
        )
        result.append(text)
    return result


def parse_sheet_column_a(sheet_xml: bytes, shared_strings: list[str]) -> dict[int, str]:
    """
    Parse xl/worksheets/sheet1.xml and return {1-based row index: cell A value}.
    Handles both inline strings and shared string references (t="s").
    """
    import xml.etree.ElementTree as ET
    root = ET.fromstring(sheet_xml)
    ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    row_to_char: dict[int, str] = {}

    for row_el in root.iter(f"{{{ns}}}row"):
        row_idx = int(row_el.attrib.get("r", 0))
        for cell_el in row_el:
            ref = cell_el.attrib.get("r", "")
            if not ref.startswith("A"):
                continue
            cell_type = cell_el.attrib.get("t", "")
            val_el = cell_el.find(f"{{{ns}}}v")
            if val_el is None or not val_el.text:
                continue
            if cell_type == "s":
                # Shared string index
                idx = int(val_el.text)
                value = shared_strings[idx] if idx < len(shared_strings) else val_el.text
            else:
                value = val_el.text.strip()
            row_to_char[row_idx] = value

    return row_to_char


def parse_drawing_row_to_media(drawing_xml: bytes, drawing_rels: bytes) -> dict[int, str]:
    """
    Parse xl/drawings/drawing1.xml + its .rels file.
    Returns {1-based row index: media filename inside xl/media/}.

    DrawingML twoCellAnchors look like:
      <xdr:twoCellAnchor>
        <xdr:from><xdr:row>N</xdr:row>...</xdr:from>
        ...
        <xdr:pic>
          <xdr:blipFill>
            <a:blip r:embed="rId3"/>
          </xdr:blipFill>
        </xdr:pic>
      </xdr:twoCellAnchor>

    The .rels file maps rId → media file.
    """
    import xml.etree.ElementTree as ET

    # 1. Parse relationships: rId → target (e.g. "../media/image1.png")
    rels_root  = ET.fromstring(drawing_rels)
    rid_to_target: dict[str, str] = {}
    for rel in rels_root:
        rid    = rel.attrib.get("Id", "")
        target = rel.attrib.get("Target", "")
        rid_to_target[rid] = target  # e.g. "../media/image1.png"

    # 2. Parse drawing XML
    draw_root = ET.fromstring(drawing_xml)
    row_to_media: dict[int, str] = {}

    for anchor in draw_root:
        tag = strip_ns(anchor.tag)
        if tag not in ("twoCellAnchor", "oneCellAnchor", "absoluteAnchor"):
            continue

        # Get the "from" row (0-based in DrawingML → convert to 1-based)
        from_el = anchor.find(
            "{http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing}from"
        )
        row_zero = None
        if from_el is not None:
            row_el = from_el.find(
                "{http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing}row"
            )
            if row_el is not None and row_el.text is not None:
                row_zero = int(row_el.text)

        if row_zero is None:
            continue

        row_one = row_zero + 1  # convert to 1-based to match sheet rows

        # Find the blip embed relationship id
        blip = anchor.find(
            ".//{http://schemas.openxmlformats.org/drawingml/2006/main}blip"
        )
        if blip is None:
            continue

        rid = blip.attrib.get(
            "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}embed", ""
        )
        if not rid:
            continue

        target = rid_to_target.get(rid, "")
        if not target:
            continue

        # Normalise path: "../media/image1.png" → "xl/media/image1.png"
        media_name = Path(target).name   # e.g. "image1.png"
        row_to_media[row_one] = media_name

    return row_to_media


def safe_char_filename(char: str) -> str:
    """
    Convert a character/label to a safe filename component.
    'A' → 'A', '10' → '10', 'Space' → 'SPACE', etc.
    """
    return re.sub(r'[^\w\-]', '_', char.strip()).upper()


def main() -> None:
    if not EXCEL_PATH.exists():
        raise FileNotFoundError(f"Excel file not found: {EXCEL_PATH}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Reading: {EXCEL_PATH}")

    with zipfile.ZipFile(EXCEL_PATH, "r") as z:
        names = z.namelist()

        # ── Sheet data ──────────────────────────────────────────────────────
        sheet_path = "xl/worksheets/sheet1.xml"
        if sheet_path not in names:
            # Try to find it
            sheet_path = next((n for n in names if re.match(r"xl/worksheets/sheet\d+\.xml", n)), None)
            if not sheet_path:
                raise ValueError("Cannot find sheet1.xml inside the Excel file.")

        sheet_xml = z.read(sheet_path)
        shared_strings = parse_shared_strings(z)
        row_to_char = parse_sheet_column_a(sheet_xml, shared_strings)
        print(f"  Found {len(row_to_char)} character entries in Column A")

        # ── Drawing data ─────────────────────────────────────────────────────
        drawing_path = "xl/drawings/drawing1.xml"
        drawing_rels_path = "xl/drawings/_rels/drawing1.xml.rels"

        if drawing_path not in names:
            print("[WARN] No drawing1.xml found — no embedded images to extract.")
            print("       Please check that images are embedded (not linked) in the Excel file.")
            return

        drawing_xml  = z.read(drawing_path)
        drawing_rels = z.read(drawing_rels_path) if drawing_rels_path in names else b"<Relationships/>"
        row_to_media = parse_drawing_row_to_media(drawing_xml, drawing_rels)
        print(f"  Found {len(row_to_media)} embedded images in the drawing")

        # ── Extract and save ─────────────────────────────────────────────────
        manifest: dict[str, str] = {}
        saved = 0
        skipped = 0

        for row_idx, char_label in sorted(row_to_char.items()):
            media_name = row_to_media.get(row_idx)
            if not media_name:
                print(f"  [SKIP] Row {row_idx} '{char_label}' — no image found for this row")
                skipped += 1
                continue

            media_zip_path = f"xl/media/{media_name}"
            if media_zip_path not in names:
                print(f"  [SKIP] Row {row_idx} '{char_label}' — media file missing: {media_zip_path}")
                skipped += 1
                continue

            img_bytes = z.read(media_zip_path)
            safe_name = safe_char_filename(char_label)
            out_path  = OUT_DIR / f"{safe_name}.png"

            if HAS_PILLOW:
                try:
                    img = Image.open(BytesIO(img_bytes))
                    img.save(out_path, "PNG", optimize=True)
                except Exception as e:
                    print(f"  [WARN] Could not convert '{char_label}' image to PNG ({e}); saving raw.")
                    raw_ext = Path(media_name).suffix
                    out_path = OUT_DIR / f"{safe_name}{raw_ext}"
                    out_path.write_bytes(img_bytes)
            else:
                # No Pillow — save with original extension
                raw_ext = Path(media_name).suffix
                out_path = OUT_DIR / f"{safe_name}{raw_ext}"
                out_path.write_bytes(img_bytes)

            # Map the normalised uppercase key → filename
            manifest[safe_name] = out_path.name
            print(f"  [OK] Row {row_idx:3d}  '{char_label}'  ->  {out_path.name}")
            saved += 1

    # ── Write manifest ───────────────────────────────────────────────────────
    MANIFEST_OUT.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
    print(f"\nDone. {saved} images saved, {skipped} skipped.")
    print(f"Manifest: {MANIFEST_OUT}")
    print(f"Output:   {OUT_DIR}")

    if skipped > 0:
        print("\n[INFO] Skipped rows may have images in a different drawing sheet.")
        print("       Check 'xl/drawings/' inside the .xlsx ZIP for additional drawing files.")


if __name__ == "__main__":
    main()
