#!/usr/bin/env python3
import argparse
import csv
import os
import sys
import glob
from typing import Dict, Tuple, Optional, List

from log import log
from util import smart_open

csv.field_size_limit(sys.maxsize)

# Target columns in the exact requested order
TARGET_FIELDS = [
    "title",
    "dbms",
    "version",
    "query",
    "state",
    "client_total",
    "client_total_mean",
    "client_total_median",
    "total",
    "total_mean",
    "total_median",
    "execution",
    "execution_mean",
    "execution_median",
    "compilation",
    "compilation_mean",
    "compilation_median",
    "rows",
    "message",
    "extra",
    "result",
    "plan",
]


def truthy(val: str) -> bool:
    if val is None:
        return False
    return str(val).strip().lower() in ("1", "true", "yes", "y", "t")


def derive_state_and_message(row: Dict[str, str]) -> Tuple[str, str]:
    # Prefer explicit state/message if present
    state = row.get("state")
    message = row.get("message")
    if not state:
        # Priority: fatal > oom > global_timeout > timeout > error
        if truthy(row.get("fatal")):
            state = "fatal"
        elif truthy(row.get("oom")):
            state = "oom"
        elif truthy(row.get("global_timeout")):
            state = "global_timeout"
        elif truthy(row.get("timeout")):
            state = "timeout"
        elif row.get("error") and str(row.get("error")).strip() != "":
            state = "error"
        else:
            state = "success"
        message = row.get("error", "").strip()

    return state, message


def rewrite_row(old: Dict[str, str], anonymize: Optional[str] = None) -> Dict[str, str]:
    out: Dict[str, str] = {k: "" for k in TARGET_FIELDS}

    # Copy straightforward fields if present
    for f in ("title", "dbms", "version", "query", "client_total", "client_total_mean", "client_total_median",
              "total", "total_mean", "total_median", "execution", "execution_mean", "execution_median",
              "compilation", "compilation_mean", "compilation_median", "rows", "extra", "result", "plan"):
        if f in old:
            out[f] = old.get(f, "")

    # If anonymization requested, replace title and dbms with placeholder
    if anonymize is not None:
        out["title"] = anonymize
        out["dbms"] = anonymize

    # Derive state and message
    state, message = derive_state_and_message(old)
    out["state"] = state
    out["message"] = "error message was redacted" if anonymize and message else message

    return out


def rewrite_file(input_path: str, output_path: str, overwrite: bool = False, anonymize: Optional[str] = None) -> None:
    if not overwrite and os.path.exists(output_path):
        raise FileExistsError(f"Output file {output_path} already exists.")

    with smart_open(input_path, newline='', encoding='utf-8') as inf, \
            smart_open(output_path, 'wt', newline='', encoding='utf-8') as outf:
        reader = csv.DictReader(inf)
        writer = csv.DictWriter(outf, fieldnames=TARGET_FIELDS)
        writer.writeheader()

        for row in reader:
            newrow = rewrite_row(row, anonymize=anonymize)
            writer.writerow(newrow)


def rewrite_directory(dir: str, compress: bool, anonymize: Optional[str] = None, patterns: List[str] = []) -> None:
    files = glob.glob(os.path.join(dir, '*.csv'))
    if not files:
        log.info(f"No files found in {dir} matching pattern `*.csv`")
        return

    # If anonymizing, require patterns
    out_dir = dir
    if anonymize is not None:
        if not patterns:
            log.error("Anonymization requested but no --patterns provided")
            raise ValueError("--patterns is required when --anonymize is used")

        for p in patterns:
            out_dir = out_dir.replace(p, anonymize)

        os.makedirs(out_dir, exist_ok=True)
        overwrite = False  # do not overwrite existing files in anonymization mode
    else:
        overwrite = True

    with log.progress("Compressing files", total=len(files)) as progress:
        for f in files:
            base = os.path.basename(f)
            if anonymize is not None:
                # write into the specified out_dir, keep base name, add extension if compress
                outbase = base + (".gz" if compress else "")
                outpath = os.path.join(out_dir, outbase)

                for p in patterns:
                    outpath = outpath.replace(p, anonymize)
            else:
                outpath = os.path.join(out_dir, base + (".gz" if compress else ".tmp"))

            progress.description(base)

            # If output already exists, skip only when the output is newer-or-equal than the input.
            if os.path.exists(outpath):
                try:
                    src_mtime = os.path.getmtime(f)
                    dst_mtime = os.path.getmtime(outpath)
                except OSError:
                    src_mtime = dst_mtime = None

                if src_mtime is not None and dst_mtime is not None and dst_mtime >= src_mtime:
                    log.info(f"Skipping {f}: target {outpath} is newer or same age")
                    progress.advance()
                    continue
                else:
                    # Target exists but is older than source: allow overwrite regardless of anonymize default
                    local_overwrite = True
            else:
                local_overwrite = overwrite

            log.info(f"Compressing {f} -> {outpath}")
            try:
                rewrite_file(f, outpath, overwrite=local_overwrite, anonymize=anonymize)
                if not compress and anonymize is None:
                    os.replace(outpath, f)
            except Exception as e:
                log.error(f"Failed to compress {f}: {e}")

            progress.advance()


def main():
    log.header("Compressing Result CSVs")

    parser = argparse.ArgumentParser(description="Rewrite result CSVs to the new schema")
    parser.add_argument('dir', help='Directory containing CSV files')
    parser.add_argument('--compress', '-c', default=True, action='store_false', help='Compress output files with gzip (default: true)')
    parser.add_argument('--anonymize', '-a', help='If set, replace title and dbms, and patterns in the filename with this placeholder')
    parser.add_argument('--patterns', '-p', nargs='+', default=[], help='Patterns to anonymize')
    args = parser.parse_args()

    rewrite_directory(args.dir, args.compress, anonymize=args.anonymize, patterns=args.patterns)


if __name__ == '__main__':
    main()
