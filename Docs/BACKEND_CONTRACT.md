# Vokabel Backend Contract

The backend owns the canonical vocabulary catalog. Apps keep local progress events and ask the backend for catalog and progress synchronization.

## Responsibilities

- Store `MASTER_vokabelheft_norwegisch.csv` as the canonical catalog.
- Accept new vocabulary batches from an admin/import flow.
- Validate and normalize new entries before writing them to the master catalog.
- Preserve existing CSV IDs and assign stable IDs to new rows.
- Publish a new catalog version whenever the master catalog changes.
- Let devices ask whether new or corrected vocabulary is available.
- Merge device progress events and return the merged event stream.

## CSV Rules

The backend catalog uses the app catalog header without progress columns:

```text
ID,Deutsch,Norwegisch,Artikel,Wortart,Herkunft,Lektion,Beispielsatz_NO,Beispielsatz_DE,Notiz,Aktiv
```

Progress is not written into the master catalog. Devices send progress as event JSON, and the backend stores those events separately.

## Device Sync

### `POST /v1/sync`

Request:

```json
{
  "deviceID": "device-uuid",
  "knownCatalogEntryIDs": ["NO0001", "NO0002"],
  "progressEvents": [
    {
      "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE1",
      "entryID": "NO0001",
      "learner": "Papa",
      "timestamp": "2026-05-04T08:00:00Z",
      "grade": "richtig",
      "correctLevelDelta": 1
    }
  ]
}
```

Response:

```json
{
  "catalogCSV": "ID,Deutsch,Norwegisch,Artikel,Wortart,Herkunft,Lektion,Beispielsatz_NO,Beispielsatz_DE,Notiz,Aktiv\n...",
  "progressEvents": [],
  "catalogVersion": "2026-05-04T08:15:00Z",
  "newVocabularyCount": 2,
  "correctedVocabularyCount": 1
}
```

The backend deduplicates progress events by `id`, stores new events, and returns all events that should be known by the device.

## Vocabulary Update Check

### `POST /v1/vocabulary/updates`

Request:

```json
{
  "deviceID": "device-uuid",
  "knownCatalogEntryIDs": ["NO0001", "NO0002"]
}
```

Response when updates exist:

```json
{
  "catalogCSV": "ID,Deutsch,Norwegisch,Artikel,Wortart,Herkunft,Lektion,Beispielsatz_NO,Beispielsatz_DE,Notiz,Aktiv\n...",
  "catalogVersion": "2026-05-04T08:15:00Z",
  "newVocabularyCount": 2,
  "correctedVocabularyCount": 1
}
```

Response when no updates exist:

```json
{
  "catalogCSV": null,
  "catalogVersion": "2026-05-04T08:15:00Z",
  "newVocabularyCount": 0,
  "correctedVocabularyCount": 0
}
```

## Admin Vocabulary Import

### `POST /v1/admin/vocabulary/import`

This endpoint is for the backend/admin surface, not regular app devices.

Request:

```json
{
  "entries": [
    {
      "deutsch": "der tablett",
      "norwegisch": "brettet",
      "artikel": "et",
      "wortart": "Substantiv",
      "herkunft": "Norsk for deg",
      "lektion": "Lektion 7",
      "beispielsatzNO": "",
      "beispielsatzDE": "",
      "notiz": "",
      "aktiv": "ja"
    }
  ]
}
```

Backend behavior:

- Reject rows without German or Norwegian text.
- Normalize article values to `en`, `et`, or `en/ei`.
- Reject articles on non-noun rows.
- Strip legacy article suffixes like `"dag, en"` into separate word and article fields.
- Detect duplicates by normalized German/Norwegian/article/source/lesson.
- Append accepted entries to the master catalog.
- Return the assigned IDs and the new `catalogVersion`.
- Notify subscribed devices, or expose the new version through `/v1/vocabulary/updates` for polling.
