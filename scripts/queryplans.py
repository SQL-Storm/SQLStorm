#!/usr/bin/env python3
import argparse
import csv
from dataclasses import dataclass
import json

from distinct import Result
from log import log
from util import smart_open, sort_query_list

operators = ["Join", "GroupBy", "GroupJoin", "TableScan", "Select", "Iteration", "SetOperation", "RegexSplit"]


@dataclass
class Operator:
    label: str
    id: int
    estimated_cardinality: int
    exact_cardinality: int
    qerror: float
    depth: int
    children: list[int]


@dataclass
class Result:
    query: str
    system: str
    tree: dict[int, Operator]


def analyze_plan(plan: dict, ops: dict):
    counter = -2

    label = plan["_label"]
    if "operator_id" not in plan["_attrs"]:
        plan["_attrs"]["operator_id"] = counter
        counter -= 1
    operator_id = plan["_attrs"]["operator_id"]
    estimated_cardinality = 0 if "estimated_cardinality" not in plan["_attrs"] else plan["_attrs"]["estimated_cardinality"]
    exact_cardinality = plan["_attrs"]["exact_cardinality"]
    qerror = max(estimated_cardinality, 1) / max(exact_cardinality, 1)  # > 1 if overestimation, < 1 if underestimation
    children = []
    depth = 0

    for child in plan["_children"]:
        if "operator_id" not in child["_attrs"]:
            child["_attrs"]["operator_id"] = counter
            counter -= 1
        child_id = child["_attrs"]["operator_id"]
        analyze_plan(child, ops)
        children.append(child_id)
        depth += ops[child_id].depth

    # Increment depth if operator is join, groupby, or groupjoin
    if label in operators and label != "TableScan":
        depth += 1

    ops[operator_id] = Operator(label, operator_id, estimated_cardinality, exact_cardinality, qerror, depth, children)


def analyze(result_file):
    queries = {}

    with log.progress("Loading the data", total=0) as progress:
        with smart_open(result_file, newline='', encoding='utf-8', search=True) as csvfile:
            reader = csv.DictReader(csvfile)

            for row in reader:
                query = row['query']
                system = row['dbms']
                progress.description(query)

                if row["state"] != "success" or row["plan"] == "":
                    progress.advance()
                    continue

                plan = json.loads(row["plan"])
                ops = {}
                analyze_plan(plan["queryPlan"], ops)
                queries[query] = Result(query, system, ops)

                progress.advance()

    return queries


def compute(result_file, output_file):
    queries: dict[str, Result] = analyze(result_file)

    log.info(f"Writing results to {output_file} ...")

    # Use context managers to ensure files are closed even if an error occurs.
    with smart_open(output_file, 'wt', newline='', encoding='utf-8') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=["query", "system", "label", "operator_id", "estimated_cardinality", "exact_cardinality", "qerror", "depth", "children"])
        writer.writeheader()

        with log.progress("Writing query plans", len(queries)) as progress:
            for q in sort_query_list(queries.keys()):
                progress.description(q)
                query = queries[q]
                for op_id in sorted(query.tree.keys()):
                    op = query.tree[op_id]
                    writer.writerow({
                        "query": q,
                        "system": query.system,
                        "label": op.label,
                        "operator_id": op.id,
                        "estimated_cardinality": op.estimated_cardinality,
                        "exact_cardinality": op.exact_cardinality,
                        "qerror": op.qerror,
                        "depth": op.depth,
                        "children": op.children
                    })

                progress.advance()


def compute_aggregations(result_file, output_file):
    queries: dict[str, Result] = analyze(result_file)

    with smart_open(output_file, 'wt', newline='', encoding='utf-8') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=["query", "system", "operator_id", "input_estimated", "input_exact", "input_label", "output_estimated", "output_exact", "depth"])
        writer.writeheader()

        with log.progress("Writing aggregations", len(queries)) as progress:
            for q in sort_query_list(queries.keys()):
                progress.description(q)
                query = queries[q]
                for op_id in sorted(query.tree.keys()):
                    op = query.tree[op_id]
                    if op.label in ["GroupBy"] and len(op.children) == 1:
                        input = query.tree[op.children[0]]
                        writer.writerow({
                            "query": q,
                            "system": query.system,
                            "operator_id": op.id,
                            "input_estimated": input.estimated_cardinality,
                            "input_exact": input.exact_cardinality,
                            "input_label": input.label,
                            "output_estimated": op.estimated_cardinality,
                            "output_exact": op.exact_cardinality,
                            "depth": op.depth
                        })

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
