#!/usr/bin/env python3
"""Align existing ARM evidence in a customer project with the current contract.

Two capture-path defects left historical documents inconsistent:

1. Timestamps were written as ISO-8601 strings instead of Firestore timestamps.
   Firestore orders by value type before value, so a collection holding both
   cannot be ordered or paged on those fields.
2. Cases carried no `status`, so readers inferred triage state from `handled` —
   the capture-time "did the app catch this" flag — and showed untouched cases
   as Resolved.

This rewrites only those fields, through an update mask, and never touches
`handled` or any existing operator triage.

Dry run (default) prints the exact planned changes and writes nothing:

  python3 backfill_arm_evidence.py --project luminary-axis-dashboard \
      --account you@example.com

Apply, after reviewing the plan:

  python3 backfill_arm_evidence.py --project luminary-axis-dashboard \
      --account you@example.com --apply --backup ./arm-backup.json
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

FIRESTORE = "https://firestore.googleapis.com/v1"

# Capture-time fields that must hold a real Firestore timestamp.
TIMESTAMP_FIELDS = {
    "armIssues": ("firstSeenAt", "lastSeenAt"),
    "armCases": ("createdAt",),
}

CASE_STATUS_NEW = "new"
VALID_CASE_STATUS = {"new", "acknowledged", "triaging", "monitoring", "resolved", "closed"}


def token(account: str) -> str:
    return subprocess.run(
        ["gcloud", "auth", "print-access-token", "--account", account],
        capture_output=True, check=True, text=True,
    ).stdout.strip()


def request(method: str, url: str, bearer: str, body: dict | None = None) -> dict:
    payload = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=payload, method=method)
    req.add_header("Authorization", f"Bearer {bearer}")
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            text = response.read().decode()
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {url} failed ({error.code}): {error.read().decode()[:400]}")
    return json.loads(text) if text else {}


def list_documents(project: str, collection: str, bearer: str) -> list[dict]:
    documents: list[dict] = []
    page = None
    while True:
        url = f"{FIRESTORE}/projects/{project}/databases/(default)/documents/{collection}?pageSize=300"
        if page:
            url += f"&pageToken={urllib.parse.quote(page)}"
        body = request("GET", url, bearer)
        documents.extend(body.get("documents", []))
        page = body.get("nextPageToken")
        if not page:
            return documents


def plan(document: dict, collection: str) -> dict[str, dict]:
    """Return the fields that need rewriting for one document."""
    fields = document.get("fields", {})
    changes: dict[str, dict] = {}

    for name in TIMESTAMP_FIELDS[collection]:
        value = fields.get(name)
        if value is None or "stringValue" not in value:
            continue
        raw = value["stringValue"]
        # Only rewrite values that are genuinely timestamps.
        if not raw.endswith("Z") or "T" not in raw:
            continue
        changes[name] = {"timestampValue": raw}

    if collection == "armCases":
        status = fields.get("status", {}).get("stringValue")
        if status is None:
            # Untriaged. Never inferred from `handled`.
            changes["status"] = {"stringValue": CASE_STATUS_NEW}
        elif status not in VALID_CASE_STATUS and status.lower() in VALID_CASE_STATUS:
            # Historic display-cased value such as "New".
            changes["status"] = {"stringValue": status.lower()}

    return changes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--account", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--backup", type=pathlib.Path)
    args = parser.parse_args()

    if args.apply and args.backup is None:
        raise SystemExit("--apply requires --backup so the originals are recoverable.")

    bearer = token(args.account)
    originals: dict[str, list[dict]] = {}
    planned: list[tuple[str, str, dict[str, dict]]] = []

    for collection in ("armIssues", "armCases"):
        documents = list_documents(args.project, collection, bearer)
        originals[collection] = documents
        print(f"{collection}: {len(documents)} documents")
        for document in documents:
            changes = plan(document, collection)
            if changes:
                planned.append((document["name"], collection, changes))

    print(f"\n{len(planned)} documents need changes:\n")
    summary: dict[str, int] = {}
    for name, _collection, changes in planned:
        for field in changes:
            summary[field] = summary.get(field, 0) + 1
        print(f"  {name.split('/')[-1]:30} {', '.join(sorted(changes))}")
    print("\nfield totals:")
    for field, count in sorted(summary.items()):
        print(f"  {field:16} {count}")

    if not args.apply:
        print("\nDry run. Nothing was written. Re-run with --apply --backup PATH.")
        return 0

    args.backup.write_text(json.dumps(originals, indent=2))
    print(f"\nWrote originals to {args.backup}")

    for index, (name, _collection, changes) in enumerate(planned, start=1):
        mask = "&".join(f"updateMask.fieldPaths={urllib.parse.quote(f)}" for f in changes)
        url = f"{FIRESTORE}/{name}?{mask}&currentDocument.exists=true"
        request("PATCH", url, bearer, {"fields": changes})
        print(f"  [{index}/{len(planned)}] {name.split('/')[-1]}")

    print(f"\nUpdated {len(planned)} documents.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
