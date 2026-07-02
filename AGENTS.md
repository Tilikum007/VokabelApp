# VokabelApp

Diese App ist der native Trainer fuer Patricks norwegische Vokabeln.

## Kanonische Datenquelle

- Die kanonische Vokabelquelle ist das laufende Backend:
  `/Users/patrickstange/Library/Application Support/VokabelAppBackend/data/MASTER_vokabelheft_norwegisch.csv`
- Die Backend-Version steht in:
  `/Users/patrickstange/Library/Application Support/VokabelAppBackend/data/catalog_version.txt`
- `Sources/VokabelCore/Resources/MASTER_vokabelheft_norwegisch.csv` ist nur Bootstrap-/Fallback-Snapshot fuer App-Start und Tests.
- `Backend/Data/` ist Git-ignorierte lokale Runtime-Data und nicht kanonisch.

## Arbeitsregeln

- IDs nie aendern.
- CSV-Struktur nicht ohne ausdruecklichen Auftrag aendern.
- Neue Vokabeln ueber Backend-/Importlogik oder bewusst parserbasiert in der laufenden Backend-Datenquelle einpflegen.
- Nach Katalogaenderungen `catalog_version.txt` aktualisieren und den App-Resource-Snapshot aus dem Backend refreshen.
- Bei App-Aenderungen `Docs/BACKEND_CONTRACT.md` beachten.

## Checks

- Swift-Build: `swift build`
- App-Checks: `swift run VokabelAppChecks`
- Backend-Checks: `python3 Backend/vokabel_backend.py --check`
- `swift test` ist aktuell nicht aussagekraeftig, weil kein Test-Target existiert.
