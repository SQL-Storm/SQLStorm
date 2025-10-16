import datetime
import decimal
from functools import cmp_to_key
import os
from typing import List

import simplejson as json
import re

import gzip
import bz2
import lzma


def smart_open(filename, mode='rt', search=False, **kwargs):
    """
    Open a file that may be compressed (gzip, bz2, lzma) or uncompressed.
    Mode 'rt' or 'rb' is recommended for text/binary files.
    """
    if search:
        for ending in ['.gz', '.bz2', '.xz', '.lzma']:
            if os.path.exists(filename + ending):
                filename += ending
                break

    if filename.endswith('.gz'):
        return gzip.open(filename, mode, **kwargs)
    elif filename.endswith('.bz2'):
        return bz2.open(filename, mode, **kwargs)
    elif filename.endswith('.xz') or filename.endswith('.lzma'):
        return lzma.open(filename, mode, **kwargs)
    else:
        return open(filename, mode, **kwargs)


def natural_sort_key(filename):
    """
    Extract the numeric part of the filename before the `.sql` extension.

    Args:
        filename (str): Filename to extract the numeric part from.

    Returns:
        tuple: A tuple containing the numeric part and the rest of the filename.
    """
    match = re.match(r'(\d+)', filename)
    if match:
        number = int(match.group(1))
        suffix = filename[match.end():].split('.')[0]
        return (number, suffix)
    return (float('inf'), filename)  # Handle cases where no number is found


def sort_query_list(query_list: List[str]):
    """
    Sort a list of query filenames in natural order.

    Args:
        query_list (List[str]): List of query filenames to sort.

    Returns:
        List[str]: Sorted list of query filenames.
    """
    return sorted(query_list, key=natural_sort_key)


def is_in_comment(content: str, p=False) -> int:
    """Count occurrences of keyword in content that are not inside a string literal or comment.

    Supports SQL single-line comments starting with --, block comments /* */ and single/double-quoted strings.
    Search is case-insensitive and ensures keyword is a standalone word (boundaries are non-alphanumeric/_).
    """
    n = len(content)
    i = 0
    in_single = False
    in_double = False
    in_line_comment = False
    in_block_comment = False

    while i < n:
        ch = content[i]
        # handle start/end of line comment
        if in_line_comment:
            if ch == '\n':
                in_line_comment = False
            i += 1
            continue

        # handle block comments
        if in_block_comment:
            if ch == '*' and i + 1 < n and content[i + 1] == '/':
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue

        # handle string literals
        if in_single:
            if ch == "'":
                # SQL escapes single quotes by doubling
                if i + 1 < n and content[i + 1] == "'":
                    i += 2
                    continue
                else:
                    in_single = False
            i += 1
            continue
        if in_double:
            if ch == '"':
                if i + 1 < n and content[i + 1] == '"':
                    i += 2
                    continue
                else:
                    in_double = False
            i += 1
            continue

        # not in any comment or string: detect comment/string starts
        if ch == '-' and i + 1 < n and content[i + 1] == '-':
            in_line_comment = True
            i += 2
            continue
        if ch == '/' and i + 1 < n and content[i + 1] == '*':
            in_block_comment = True
            i += 2
            continue
        if ch == "'":
            in_single = True
            i += 1
            continue
        if ch == '"':
            in_double = True
            i += 1
            continue

        i += 1

    if p:
        print(f"in_single={in_single}, in_double={in_double}, in_line_comment={in_line_comment}, in_block_comment={in_block_comment}")

    return in_single or in_double or in_line_comment or in_block_comment


def find_keyword_not_in_comments(content: str, keyword: str, is_word: bool = True) -> int:
    """Find the first occurrence of keyword in content that is not inside a string literal or comment.

    Supports SQL single-line comments starting with --, block comments /* */ and single/double-quoted strings.
    Search is case-insensitive and ensures keyword is a standalone word (boundaries are non-alphanumeric/_).
    Returns the index in the original content or -1 if not found.
    """
    lower = content.lower()
    key = keyword.lower()
    n = len(content)
    i = 0
    in_single = False
    in_double = False
    in_line_comment = False
    in_block_comment = False

    def is_word_boundary(pos_start: int, pos_end: int) -> bool:
        # pos_start is index of first char, pos_end is index after last char
        if is_word and pos_start > 0:
            prev = content[pos_start - 1]
            if prev.isalnum() or prev == '_':
                return False
        if is_word and pos_end < n:
            nxt = content[pos_end]
            if nxt.isalnum() or nxt == '_':
                return False
        return True

    while i < n:
        ch = content[i]
        # handle start/end of line comment
        if in_line_comment:
            if ch == '\n':
                in_line_comment = False
            i += 1
            continue

        # handle block comments
        if in_block_comment:
            if ch == '*' and i + 1 < n and content[i + 1] == '/':
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue

        # handle string literals
        if in_single:
            if ch == "'":
                # SQL escapes single quotes by doubling
                if i + 1 < n and content[i + 1] == "'":
                    i += 2
                    continue
                else:
                    in_single = False
            i += 1
            continue
        if in_double:
            if ch == '"':
                if i + 1 < n and content[i + 1] == '"':
                    i += 2
                    continue
                else:
                    in_double = False
            i += 1
            continue

        # not in any comment or string: detect comment/string starts
        if ch == '-' and i + 1 < n and content[i + 1] == '-':
            in_line_comment = True
            i += 2
            continue
        if ch == '/' and i + 1 < n and content[i + 1] == '*':
            in_block_comment = True
            i += 2
            continue
        if ch == "'":
            in_single = True
            i += 1
            continue
        if ch == '"':
            in_double = True
            i += 1
            continue

        # check for keyword here (case-insensitive)
        if lower.startswith(key, i):
            start = i
            end = i + len(key)
            if is_word_boundary(start, end):
                return start
        i += 1
    return -1


def compare_arrays(a: list[any], b: list[any]) -> int:
    """
    Compare two arrays element by element for sorting and equality.

    Args:
        a (list[any]): First array to compare.
        b (list[any]): Second array to compare.

    Returns:
        int: -1 if a < b, 1 if a > b, 0 if equal.
    """
    assert len(a) == len(b)
    for val1, val2 in zip(a, b):
        if val1 is None and val2 is None:
            continue  # Both are None, considered equal
        if val1 is None:
            return -1  # None comes first
        if val2 is None:
            return 1  # None comes first

        if isinstance(val1, list) and isinstance(val2, list):
            length = min(len(val1), len(val2))
            cmp = compare_arrays(val1[:length], val2[:length])
            if cmp != 0:
                return cmp
            return len(val1) - len(val2)

        if isinstance(val1, dict) and isinstance(val2, dict):
            cmp = compare_arrays(list(val1.keys()), list(val2.keys()))
            if cmp != 0:
                return cmp
            cmp = compare_arrays(list(val1.values()), list(val2.values()))
            if cmp != 0:
                return cmp
            return 0

        try:
            cmp = (val1 > val2) - (val1 < val2)  # Standard comparison
        except TypeError as e:
            # Fallback to string comparison
            cmp = (str(val1) > str(val2)) - (str(val1) < str(val2))
        if cmp != 0:
            return cmp

    return 0


def is_numeric(value: any) -> bool:
    """
    Check if a value is numeric (int, float, or decimal).

    Args:
        value (any): The value to check.

    Returns:
        bool: True if the value is numeric, False otherwise.
    """
    return isinstance(value, (int, float, decimal.Decimal))


def compare_values(val1: any, val2: any, ignore_decimal_points=False, ignore_microseconds=False) -> bool:
    """
    Compare two values, handling decimals and strings with tolerance/whitespace.

    Args:
        val1 (any): First value to compare.
        val2 (any): Second value to compare.

    Returns:
        bool: True if values are considered equal, False otherwise.
    """
    if is_numeric(val1) and is_numeric(val2):
        return abs(val1 - val2) < 1e-4 or (ignore_decimal_points and int(val1) == int(val2))
    elif isinstance(val1, str) and isinstance(val2, str):
        return val1.strip() == val2.strip()
    elif isinstance(val1, datetime.datetime) and isinstance(val2, datetime.datetime):
        return val1 == val2 or (ignore_microseconds and val1.replace(microsecond=0) == val2.replace(microsecond=0))
    else:
        return val1 == val2


def parse_result(result: str) -> list[any]:
    """
    Parse a database result from a JSON string and sort it.

    Args:
        result (str): A JSON-formatted string representing a list of elements.

    Returns:
        list[any]: A sorted list of elements parsed from the input string.
    """
    def parse_element(elem):
        if isinstance(elem, list):
            return [parse_element(e) for e in elem]
        if isinstance(elem, dict):
            return {k: parse_element(v) for k, v in elem.items()}
        if isinstance(elem, str):
            # Try to parse as datetime
            try:
                return datetime.datetime.fromisoformat(elem)
            except Exception:
                return elem
        return elem

    parsed = json.loads(result, use_decimal=True)
    parsed = [parse_element(row) for row in parsed]
    return sorted(parsed, key=cmp_to_key(compare_arrays))


def compare_results(result1: str, result2: str, ignore_decimal_points=False, ignore_microseconds=False) -> bool:
    """
    Compare database results for equality.

    Args:
        result1 (str): The first result to compare.
        result2 (str): The second result to compare.

    Returns:
        bool: True if the two are equal in dimensions and content, False otherwise.
    """
    if result1 == result2:
        return True

    rows1 = parse_result(result1)
    rows2 = parse_result(result2)

    if len(rows1) != len(rows2):
        return False

    for row1, row2 in zip(rows1, rows2):
        if len(row1) != len(row2):
            return False

        for val1, val2 in zip(row1, row2):
            if not compare_values(val1, val2, ignore_decimal_points=ignore_decimal_points, ignore_microseconds=ignore_microseconds):
                return False

    return True


def locate_difference(result1: str, result2: str, sys1: str, sys2: str, ignore_decimal_points=False, ignore_microseconds=False) -> str:
    """
    Locate the first difference between two database results.

    Args:
        result1 (str): The first result to compare.
        result2 (str): The second result to compare.

    Returns:
        str: A string describing the first difference found.
    """
    rows1 = parse_result(result1)
    rows2 = parse_result(result2)

    if len(rows1) != len(rows2):
        return f"Row count mismatch {len(rows1)} vs. {len(rows2)} ({sys1} vs. {sys2})"

    for row1, row2 in zip(rows1, rows2):
        if len(row1) != len(row2):
            return f"Column count mismatch {len(row1)} vs. {len(row2)} ({sys1} vs. {sys2})"

        for val1, val2 in zip(row1, row2):
            if not compare_values(val1, val2, ignore_decimal_points=ignore_decimal_points, ignore_microseconds=ignore_microseconds):
                if is_numeric(val1) and is_numeric(val2) and ignore_decimal_points:
                    val1 = int(val1)
                    val2 = int(val2)
                elif isinstance(val1, datetime.datetime) and isinstance(val2, datetime.datetime) and ignore_microseconds:
                    val1 = val1.replace(microsecond=0)
                    val2 = val2.replace(microsecond=0)
                return f"Value mismatch `{val1}` vs. `{val2}` ({sys1} vs. {sys2})"
