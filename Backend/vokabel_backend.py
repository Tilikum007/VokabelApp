#!/usr/bin/env python3
import argparse
import csv
import json
import os
import shutil
import tempfile
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import StringIO
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_MASTER = ROOT / "Sources" / "VokabelCore" / "Resources" / "MASTER_vokabelheft_norwegisch.csv"
DEFAULT_DATA_DIR = ROOT / "Backend" / "Data"
MASTER_NAME = "MASTER_vokabelheft_norwegisch.csv"
PROGRESS_NAME = "progress_events.json"
VERSION_NAME = "catalog_version.txt"

CATALOG_HEADER = [
    "ID", "Deutsch", "Norwegisch", "Artikel", "Wortart", "Herkunft", "Lektion",
    "Beispielsatz_NO", "Beispielsatz_DE", "Notiz", "Aktiv",
]

FULL_HEADER = [
    "ID", "Deutsch", "Norwegisch", "Artikel", "Wortart", "Herkunft", "Lektion",
    "Level_Papa", "Level_Mama", "Zuletzt_Papa", "Zuletzt_Mama",
    "Letztes_Ergebnis_Papa", "Letztes_Ergebnis_Mama",
    "Richtig_Papa", "Falsch_Papa", "Richtig_Mama", "Falsch_Mama",
    "Beispielsatz_NO", "Beispielsatz_DE", "Notiz", "Aktiv",
]


class VocabularyBackend:
    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.master_path = data_dir / MASTER_NAME
        self.progress_path = data_dir / PROGRESS_NAME
        self.version_path = data_dir / VERSION_NAME

    def bootstrap(self):
        self.data_dir.mkdir(parents=True, exist_ok=True)
        if not self.master_path.exists():
            shutil.copyfile(DEFAULT_SOURCE_MASTER, self.master_path)
            self._write_version()
        if not self.progress_path.exists():
            self.progress_path.write_text("[]\n", encoding="utf-8")
        if not self.version_path.exists():
            self._write_version()

    def sync(self, payload: dict) -> dict:
        progress_events = payload.get("progressEvents", [])
        merged_events = self._merge_progress_events(progress_events)
        catalog_csv = self.master_path.read_text(encoding="utf-8")
        new_count, corrected_count = self._diff_counts(payload.get("knownCatalogEntryIDs", []), catalog_csv)
        return {
            "catalogCSV": self._catalog_csv(catalog_csv),
            "progressEvents": merged_events,
            "catalogVersion": self._catalog_version(),
            "newVocabularyCount": new_count,
            "correctedVocabularyCount": corrected_count,
        }

    def vocabulary_updates(self, payload: dict) -> dict:
        catalog_csv = self.master_path.read_text(encoding="utf-8")
        new_count, corrected_count = self._diff_counts(payload.get("knownCatalogEntryIDs", []), catalog_csv)
        has_updates = new_count > 0 or corrected_count > 0
        return {
            "catalogCSV": self._catalog_csv(catalog_csv) if has_updates else None,
            "catalogVersion": self._catalog_version(),
            "newVocabularyCount": new_count,
            "correctedVocabularyCount": corrected_count,
        }

    def import_vocabulary(self, payload: dict) -> dict:
        entries = payload.get("entries", [])
        if not isinstance(entries, list):
            raise BackendError(400, "entries must be a list")

        rows = self._read_master_rows()
        existing_keys = {self._duplicate_key(row) for row in rows}
        next_number = self._next_id_number(rows)
        imported = []
        rejected = []

        for index, raw_entry in enumerate(entries):
            try:
                row = self._normalize_import_entry(raw_entry)
            except BackendError as error:
                rejected.append({"index": index, "reason": error.message})
                continue

            duplicate_key = self._duplicate_key(row)
            if duplicate_key in existing_keys:
                rejected.append({"index": index, "reason": "duplicate vocabulary entry"})
                continue

            row["ID"] = f"NO{next_number:04d}"
            next_number += 1
            existing_keys.add(duplicate_key)
            rows.append(row)
            imported.append({"id": row["ID"], "deutsch": row["Deutsch"], "norwegisch": row["Norwegisch"]})

        if imported:
            self._write_master_rows(rows)
            self._write_version()

        return {
            "imported": imported,
            "rejected": rejected,
            "catalogVersion": self._catalog_version(),
        }

    def _read_master_rows(self) -> list[dict]:
        text = self.master_path.read_text(encoding="utf-8-sig")
        reader = csv.DictReader(StringIO(text))
        return [self._catalog_row(row) for row in reader]

    def _write_master_rows(self, rows: list[dict]):
        output = StringIO()
        writer = csv.DictWriter(output, fieldnames=CATALOG_HEADER, lineterminator="\n")
        writer.writeheader()
        for row in sorted(rows, key=lambda item: item["ID"]):
            writer.writerow({key: row.get(key, "") for key in CATALOG_HEADER})
        self.master_path.write_text(output.getvalue(), encoding="utf-8")

    def _catalog_csv(self, text: str) -> str:
        rows = [self._catalog_row(row) for row in csv.DictReader(StringIO(text.lstrip("\ufeff")))]
        output = StringIO()
        writer = csv.DictWriter(output, fieldnames=CATALOG_HEADER, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
        return output.getvalue()

    def _catalog_row(self, row: dict) -> dict:
        return {
            "ID": row.get("ID", ""),
            "Deutsch": row.get("Deutsch", ""),
            "Norwegisch": self._strip_legacy_article(row.get("Norwegisch", ""))[0],
            "Artikel": self._normalize_article(row.get("Artikel", "") or self._strip_legacy_article(row.get("Norwegisch", ""))[1]),
            "Wortart": row.get("Wortart", ""),
            "Herkunft": self._normalize_source(row.get("Herkunft", "")),
            "Lektion": row.get("Lektion", "").strip(),
            "Beispielsatz_NO": row.get("Beispielsatz_NO", ""),
            "Beispielsatz_DE": row.get("Beispielsatz_DE", ""),
            "Notiz": row.get("Notiz", ""),
            "Aktiv": row.get("Aktiv", "") or "ja",
        }

    def _normalize_import_entry(self, raw: dict) -> dict:
        if not isinstance(raw, dict):
            raise BackendError(400, "entry must be an object")

        norwegian, legacy_article = self._strip_legacy_article(str(raw.get("norwegisch", "")).strip())
        article = self._normalize_article(str(raw.get("artikel", "") or legacy_article))
        part_of_speech = str(raw.get("wortart", "")).strip()
        german = str(raw.get("deutsch", "")).strip()

        if not german:
            raise BackendError(400, "Deutsch fehlt")
        if not norwegian:
            raise BackendError(400, "Norwegisch fehlt")
        if article and "substantiv" not in part_of_speech.lower():
            raise BackendError(400, "Artikel gesetzt, aber Wortart ist nicht Substantiv")

        return {
            "ID": "",
            "Deutsch": german,
            "Norwegisch": norwegian,
            "Artikel": article,
            "Wortart": part_of_speech,
            "Herkunft": self._normalize_source(str(raw.get("herkunft", ""))),
            "Lektion": str(raw.get("lektion", "")).strip(),
            "Beispielsatz_NO": str(raw.get("beispielsatzNO", "")),
            "Beispielsatz_DE": str(raw.get("beispielsatzDE", "")),
            "Notiz": str(raw.get("notiz", "")),
            "Aktiv": str(raw.get("aktiv", "") or "ja").strip(),
        }

    def _merge_progress_events(self, incoming: list[dict]) -> list[dict]:
        existing = self._load_progress_events()
        events_by_id = {event.get("id"): event for event in existing if event.get("id")}

        for event in incoming:
            event_id = event.get("id") if isinstance(event, dict) else None
            if not event_id:
                continue
            events_by_id[event_id] = event

        merged = sorted(events_by_id.values(), key=lambda item: (item.get("timestamp", ""), item.get("id", "")))
        self.progress_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return merged

    def _load_progress_events(self) -> list[dict]:
        try:
            data = json.loads(self.progress_path.read_text(encoding="utf-8"))
            return data if isinstance(data, list) else []
        except (OSError, json.JSONDecodeError):
            return []

    def _diff_counts(self, known_ids: list[str], catalog_csv: str) -> tuple[int, int]:
        known = set(known_ids if isinstance(known_ids, list) else [])
        rows = list(csv.DictReader(StringIO(catalog_csv.lstrip("\ufeff"))))
        new_count = sum(1 for row in rows if row.get("ID", "") not in known)
        return new_count, 0

    def _next_id_number(self, rows: list[dict]) -> int:
        numbers = []
        for row in rows:
            entry_id = row.get("ID", "")
            if entry_id.startswith("NO") and entry_id[2:].isdigit():
                numbers.append(int(entry_id[2:]))
        return max(numbers, default=0) + 1

    def _duplicate_key(self, row: dict) -> tuple[str, str, str, str, str]:
        return (
            row.get("Deutsch", "").casefold().strip(),
            row.get("Norwegisch", "").casefold().strip(),
            row.get("Artikel", "").casefold().strip(),
            row.get("Herkunft", "").casefold().strip(),
            row.get("Lektion", "").casefold().strip(),
        )

    def _strip_legacy_article(self, norwegian: str) -> tuple[str, str]:
        value = norwegian.strip()
        for article in ("en/ei", "ei/en", "en", "ei", "et"):
            suffix = f", {article}"
            if value.lower().endswith(suffix):
                return value[:-len(suffix)].strip(), article
        return value, ""

    def _normalize_article(self, value: str) -> str:
        article = value.strip().lower()
        if article in ("", "en", "et"):
            return article
        if article in ("ei", "ei/en", "en/ei"):
            return "en/ei"
        raise BackendError(400, f"Artikel ist nicht erlaubt: {value}")

    def _normalize_source(self, value: str) -> str:
        seen = set()
        tokens = []
        for token in value.split(";"):
            normalized = token.strip()
            if normalized and normalized not in seen:
                seen.add(normalized)
                tokens.append(normalized)
        return "; ".join(tokens)

    def _catalog_version(self) -> str:
        return self.version_path.read_text(encoding="utf-8").strip()

    def _write_version(self):
        stamp = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        self.version_path.write_text(stamp + "\n", encoding="utf-8")


class BackendError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


class Handler(BaseHTTPRequestHandler):
    backend: VocabularyBackend

    def do_POST(self):
        try:
            path = urlparse(self.path).path
            payload = self._read_json()
            if path == "/v1/sync":
                self._write_json(self.backend.sync(payload))
            elif path == "/v1/vocabulary/updates":
                self._write_json(self.backend.vocabulary_updates(payload))
            elif path == "/v1/admin/vocabulary/import":
                self._write_json(self.backend.import_vocabulary(payload))
            else:
                raise BackendError(404, "not found")
        except BackendError as error:
            self._write_json({"error": error.message}, status=error.status)
        except Exception as error:
            self._write_json({"error": str(error)}, status=500)

    def do_GET(self):
        if urlparse(self.path).path == "/health":
            self._write_json({"status": "ok"})
            return
        self._write_json({"error": "not found"}, status=404)

    def log_message(self, format, *args):
        print(f"{self.address_string()} - {format % args}", flush=True)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length)
        try:
            payload = json.loads(data.decode("utf-8") if data else "{}")
        except json.JSONDecodeError as error:
            raise BackendError(400, f"invalid json: {error.msg}")
        if not isinstance(payload, dict):
            raise BackendError(400, "request body must be an object")
        return payload

    def _write_json(self, payload: dict, status: int = 200):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def run_check(backend: VocabularyBackend):
    backend.bootstrap()
    before = backend.vocabulary_updates({"deviceID": "check", "knownCatalogEntryIDs": []})
    if not before["catalogCSV"]:
        raise SystemExit("expected initial catalog")

    result = backend.import_vocabulary({
        "entries": [{
            "deutsch": "Testwort",
            "norwegisch": "testord, et",
            "artikel": "",
            "wortart": "Substantiv",
            "herkunft": "Backend Check",
            "lektion": "Check",
            "aktiv": "ja",
        }]
    })
    if not result["imported"]:
        raise SystemExit("expected import to create one row")
    print("Backend checks passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=os.environ.get("VOKABEL_BACKEND_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("VOKABEL_BACKEND_PORT", "8080")))
    parser.add_argument("--data-dir", default=os.environ.get("VOKABEL_BACKEND_DATA_DIR", str(DEFAULT_DATA_DIR)))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    backend = VocabularyBackend(Path(args.data_dir))
    if args.check:
        with tempfile.TemporaryDirectory() as temp_dir:
            run_check(VocabularyBackend(Path(temp_dir)))
        return

    backend.bootstrap()
    Handler.backend = backend
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Vokabel backend listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
