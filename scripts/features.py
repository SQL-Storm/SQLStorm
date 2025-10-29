#!/usr/bin/env python3
import argparse
import csv
import json
import re

from distinct import Result
import distinct
from log import log
from util import smart_open

complexity_classes = ["low", "medium", "high"]
limits = {
    "joins": [3, 8],
    "aggregations": [1, 4],
    "sorts": [1],
    "windows": [0, 1],
    "iterations": [0, 0]
}
complexity_operators = [
    ["TableScan", "Join", "GroupBy", "Sort", "Select", "PipelineBreakerScan", "Result", "GroupJoin", "Map", "EarlyProbe", "InlineTable"],
    ["Temp", "SetOperation", "Window"],
    ["Iteration", "IterationScan", "RegexSplit", "ArrayUnnest"]]

complexity_join_type = [
    ["inner", "outer", "fullouter", "leftouter", "rightouter"],
    ["leftsingle", "rightsingle", "leftsemi", "rightsemi", "leftanti", "rightanti"],
    ["rightmark", "leftmark"]]

complexity_types = [["bool", "boolean", "smallint", "integer", "bigint", "numeric", "bignumeric", "double", "date", "timestamp", "interval", "text", "char", "char1", "varchar", "unknown", "double precision"],
                    ["text[]", "varchar[]", "integer[]", "smallint[]", "bigint[]", "char[]", "numeric[]"],
                    ["record", "jsonb", "json", "void", "timestamptz"]]

expression_categories = {
    "base": ["iuref", "const", "iu", "key", "entry", "value", "false"],
    "agg_low": ["agg_avg", "agg_count", "agg_max", "agg_min", "agg_sum", "agg_countstar", "agg_any"],
    "error": ["error"],
    "cast": ["cast"],
    "case": ["searchedcase", "simplecase", "greatestleast"],
    "comparison_low": ["compare", "in", "between", "not", "and", "or", "isnull", "isnotnull"],
    "arithmetic_low": ["sub", "mul", "div", "add", "rem", "neg"],

    "agg_medium": ["agg_stddevsamp", "agg_stringagg", "agg_arrayagg"],
    "window_medium": ["frame", "rows", "order", "op_sum", "op_rank", "op_denserank", "op_rownumber", "op_avg", "op_count", "op_countstar", "op_max", "op_min", "op_lag", "op_lead", "op_ntile", "op_firstvalue", "op_lastvalue", "op_ntile", "op_percentrank", "op_percentilecont", "op_cumedist", "op_stddevsamp", "op_nthvalue"],
    "comparison_medium": ["quantified"],
    "arithmetic_medium": ["abs", "sqrt", "exp", "log10", "pow", "round2", "ceil", "floor", "round", "random", "cos", "bitand", "bitor", "shiftleft", "shiftright", "trunc"],
    "nulls": ["coalesce", "nullif", "nullifnottrue", "trueornull"],
    "date": ["extractyear", "extractday", "extractepoch", "extractquarter", "extractmonth", "extractweek", "extracthour", "extractdow", "extractdoy", "extractisodow", "datepart", "datetrunc", "age", "to_timestamp"],
    "string matching": ["like", "ilike", "contains", "startswith", "position"],
    "string modification": ["stringconcat", "concat", "concat_ws", "substring", "left", "right", "upper", "lower", "charlength", "trimboth", "trimleading", "trimtrailing", "lpad", "initcap",
                            "replace", "split_part", "translate", "repeat", "reverse", "md5"],
    "array": ["arraylength", "arraybuild", "arrayToString", "arrayoverlap", "arrayremove", "cardinality", "arrayappend", "stringToArray", "arrayaccess", "arrayslice"],

    "json": ["accesstext"],
    "regex": ["regexp_replace", "regexp_split_to_array", "regexp_substr"],
}
expression_category_map = {exp: cat for cat, exps in expression_categories.items() for exp in exps}

complexity_expression_categories = [
    ["base", "cast", "case", "comparison_low", "arithmetic_low", "agg_low"],
    ["agg_medium", "comparison_medium", "arithmetic_medium", "string matching", "string modification", "array", "date", "nulls", "error", "window_medium"],
    ["json", "regex", "unknown"]
]


def map_complexity(val, mapping, info, comp=0):
    found = False
    for c, l in enumerate(mapping):
        if val in l:
            comp = max(comp, c)
            found = True
            break

    if not found:
        log.error(f"Unknown {info}: {val}")
        comp = len(complexity_classes) - 1

    if comp >= len(complexity_classes):
        raise Exception(f"Unknown complexity category: {comp} for {info}")

    return comp


def get_expression_category(exp):
    exp = exp.replace("aggLeft_", "agg_").replace("aggRight_", "agg_")
    exp = exp.replace("keyLeft_", "key_").replace("keyRight_", "key_")
    exp = re.sub(r'_\d+$', '', exp)

    if exp not in expression_category_map:
        log.error(f"Unknown expression: {exp}")
        return "unknown"
    return expression_category_map[exp]


def normalize_type(typ):
    if not typ:
        return ""
    return re.sub(r'\(.*\)', '', typ)


join_type_counts = {}
operator_counts = {}
expression_category_counts = {}
type_counts = {}


def count(val, counter, query):
    if val not in counter:
        counter[val] = set()
    counter[val].add(query)


def print_counter(counter, complexity_mapping, info):
    for i, keys in enumerate(complexity_mapping):
        for k in keys:
            if k in counter:
                log.info(f"{info} {k} ({complexity_classes[i]} complexity): {len(counter[k])} queries")
    log.newline()


def complexity(r: Result):
    comp = 0
    if r.attributes["state"] != "success":
        return complexity_classes[-1]

    for k in limits.keys():
        for c, l in enumerate(limits[k]):
            if k not in r.attributes.keys():
                raise Exception(f"Missing attribute {k} in result")

            if r.attributes[k] > l:
                comp = max(comp, c + 1)

    for op in r.tree.values():
        op_comp = 0
        op_comp = map_complexity(op.label, complexity_operators, "operator", op_comp)
        count(op.label, operator_counts, r.query)

        if op.label == "Join" or op.label == "GroupJoin":
            join_type = op.attributes.split("|")[1]
            op_comp = map_complexity(join_type, complexity_join_type, "join type", op_comp)
            count(join_type, join_type_counts, r.query)

        for exp in op.expression_list:
            category = get_expression_category(exp.label)
            op_comp = map_complexity(category, complexity_expression_categories, "expression category", op_comp)
            count(category, expression_category_counts, r.query)

            op_comp = map_complexity(normalize_type(exp.type), complexity_types, "expression type", op_comp)
            count(normalize_type(exp.type), type_counts, r.query)

        comp = max(comp, op_comp)
        # Add complexity attribute to operator
        op.complexity = complexity_classes[op_comp]

    return complexity_classes[comp]


def analyze(result_file):
    log.info(f"Analyzing result file: {result_file}")

    # Ensure per-run counters are reset so multiple calls to analyze don't accumulate state
    operator_counts.clear()
    join_type_counts.clear()
    expression_category_counts.clear()
    type_counts.clear()

    queries = distinct.analyze(result_file)

    complexity_counts = {c: 0 for c in complexity_classes}
    with log.progress("Computing complexity queries", len(queries)) as progress:
        for q in queries:
            progress.description(q)

            r = queries[q]
            comp = complexity(r)
            complexity_counts[comp] += 1

            r.attributes["complexity"] = comp
            r.attributes["distinct_trees"] = queries[q].distinct_trees
            r.attributes["distinct_operators"] = queries[q].distinct_operators

            progress.advance()

    print_counter(operator_counts, complexity_operators, "Operator")
    print_counter(join_type_counts, complexity_join_type, "Join type")
    print_counter(expression_category_counts, complexity_expression_categories, "Expression category")
    print_counter(type_counts, complexity_types, "Type")

    for c in complexity_classes:
        log.info(f"Complexity {c}: {complexity_counts[c]} queries")
    log.newline()

    return queries


def compute(result_file, output_file):
    queries = analyze(result_file)

    log.info(f"Writing results to {output_file} ...")

    # Use context managers to ensure files are closed even if an error occurs.
    with smart_open(output_file, 'wt', newline='', encoding='utf-8') as csvfile, \
            smart_open(output_file.replace(".csv", f"_operators.csv"), 'wt', newline='', encoding='utf-8') as csvfile_operators, \
            smart_open(output_file.replace(".csv", f"_expressions.csv"), 'wt', newline='', encoding='utf-8') as csvfile_expressions:

        writer = csv.DictWriter(csvfile, fieldnames=["query", "state", "message", "time", "rows", "allocatedBytes", "scannedRows", "querylength", "ops",
                                "scans", "joins", "aggregations", "sorts", "windows", "iterations", "distinct_trees", "distinct_operators", "complexity"])
        writer.writeheader()

        writer_operators = csv.DictWriter(csvfile_operators, fieldnames=["query", "operator", "attributes", "complexity"])
        writer_operators.writeheader()

        writer_expressions = csv.DictWriter(csvfile_expressions, fieldnames=["query", "expression", "category", "type", "attributes"])
        writer_expressions.writeheader()

        with log.progress("Writing query features", len(queries)) as progress:
            for q in queries:
                progress.description(q)
                writer.writerow(queries[q].attributes)

                for op in queries[q].tree.values():
                    # Ensure JSON serialization won't fail on unexpected objects by falling back to str
                    writer_operators.writerow({"query": q, "operator": op.label, "attributes": op.attributes, "complexity": op.complexity})

                    for exp in op.expression_list:
                        category = get_expression_category(exp.label)
                        writer_expressions.writerow({"query": q, "expression": exp.label, "category": category, "type": exp.type, "attributes": exp.attributes})

                progress.advance()


def main():
    log.header("Compute query features")

    # Get command line arguments
    argparser = argparse.ArgumentParser()
    argparser.add_argument("result", help="Result file")
    argparser.add_argument("output", help="Output file")
    args = argparser.parse_args()

    compute(args.result, args.output)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log.error(e)
        raise e
