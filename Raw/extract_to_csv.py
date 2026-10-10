"""
Flattens the SEC company facts JSON files into CSV, one file per company.

Extracts every tag, unit and field. No filtering happens here.
All selection decisions are made later in SQL.

Run:  python extract_to_csv.py
Expects the 5 .json files in the same folder as this script.
"""

import csv
import json
import os

FILES = [
    ("walmart",   "Walmart"),
    ("costco",    "Costco"),
    ("target",    "Target"),
    ("bestbuy",   "Best Buy"),
    ("homedepot", "Home Depot"),
]

HEADER = [
    "company", "tag", "unit", "period_start", "period_end",
    "accession_number", "fiscal_year", "fiscal_period", "form",
    "value", "filed_date", "frame",
]


def main():
    here = os.path.dirname(os.path.abspath(__file__))

    for stem, company in FILES:
        json_path = os.path.join(here, stem + ".json")
        csv_path = os.path.join(here, stem + ".csv")

        with open(json_path, encoding="utf-8") as fh:
            data = json.load(fh)

        usgaap = data["facts"]["us-gaap"]
        rows = 0

        with open(csv_path, "w", encoding="utf-8", newline="") as out:
            writer = csv.writer(out, quoting=csv.QUOTE_ALL, lineterminator="\n")
            writer.writerow(HEADER)

            for tag in usgaap:
                for unit, entries in usgaap[tag]["units"].items():
                    for e in entries:
                        writer.writerow([
                            company,
                            tag,
                            unit,
                            e.get("start", ""),
                            e.get("end", ""),
                            e.get("accn", ""),
                            "null" if e.get("fy") is None else e["fy"],
                            e.get("fp") or "",
                            e.get("form") or "",
                            e.get("val", ""),
                            e.get("filed", ""),
                            e.get("frame") or "",
                        ])
                        rows += 1

        print("%-12s -> %s  (%d data rows)" % (company, stem + ".csv", rows))


if __name__ == "__main__":
    main()