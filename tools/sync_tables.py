"""Serialize the first worksheet of each workbook to a Rojo StringValue."""
import argparse
import csv
from datetime import date, time, timedelta
from decimal import Decimal
from pathlib import Path
from tempfile import TemporaryDirectory

from openpyxl import load_workbook
from openpyxl.utils.datetime import to_excel

ROOT = Path(__file__).resolve().parents[1]


def cell_text(cell, epoch):
    value = cell.value
    if cell.data_type == "e":
        raise ValueError(f"{cell.coordinate}: Excel error {value}")
    if value is None:
        return ""
    if isinstance(value, (date, time, timedelta)):
        value = to_excel(value, epoch)
    if isinstance(value, float):
        return format(Decimal(str(value)), "f")
    return str(value).strip()


def serialize(path, target):
    book = load_workbook(path, read_only=True, data_only=True)
    formulas = load_workbook(path, read_only=True, data_only=False)
    try:
        with target.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, lineterminator="\r\n")
            headers = None
            for values, originals in zip(book.worksheets[0].rows, formulas.worksheets[0].rows):
                row = []
                for cell, original in zip(values, originals):
                    if original.data_type == "f" and cell.value is None:
                        raise ValueError(f"{original.coordinate}: formula has no saved result")
                    row.append(cell_text(cell, book.epoch))
                if headers is None:
                    while row and not row[-1]:
                        row.pop()
                    if not row or "" in row or len(set(row)) != len(row):
                        raise ValueError("Expected unique, non-empty headers in row 1")
                    headers = row
                    writer.writerow(row)
                elif any(row):
                    if any(row[len(headers):]):
                        raise ValueError("Found data in a column without a header")
                    writer.writerow(row[:len(headers)])
            if headers is None:
                raise ValueError("Workbook has no header row")
    finally:
        book.close()
        formulas.close()


def sync(source, output):
    if not source.is_dir():
        raise ValueError(f"Missing workbook directory: {source}")
    inputs = sorted(p for p in source.glob("*.xlsx") if not p.name.startswith("~$"))
    output.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=output.parent) as staging:
        stage = Path(staging)
        for path in inputs:
            try:
                serialize(path, stage / (path.stem + ".txt"))
            except Exception as exc:
                raise ValueError(f"{path.name}: {exc}") from exc
        names = {path.stem + ".txt" for path in inputs}
        for name in sorted(names):
            generated = stage / name
            dest = output / name
            if not dest.exists() or dest.read_bytes() != generated.read_bytes():
                generated.replace(dest)
        for dest in output.glob("*.txt"):
            if dest.name not in names:
                dest.unlink()
    print(f"Synced {len(inputs)} workbook(s) to {output}")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--source", type=Path, default=ROOT / "tables")
    args = cli.parse_args()
    sync(args.source, ROOT / "src/ReplicatedStorage/Shared/Table")
