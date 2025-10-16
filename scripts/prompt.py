#!/usr/bin/env python3
import argparse
import asyncio
from concurrent.futures import ThreadPoolExecutor, wait
import os
import sys
from xml.parsers.expat import model

import simplejson as json
import yaml
import traceback

from llm import llm
from log import log


def write_query_to_file(sql: str, dest_dir: str, filename: str, postfix: str = ".sql", comment: str = ""):
    """
    Writes a SQL query to a file.

    Args:
        sql (str): The SQL query to write.
        dest_dir (str): The directory to write the file to.
        filename (str): The filename.
        postfix (str): The file extension to use.
    """
    sql = sql.strip()
    if sql.startswith("```"):
        sql = sql.removeprefix("```").removesuffix("```")
    if sql.startswith("sql"):
        sql = sql.removeprefix("sql")
    if sql.startswith("\\n"):
        sql = sql.removeprefix("\\n")

    with open(os.path.join(dest_dir, f"{filename}{postfix}"), 'w') as f:
        f.write(comment)
        f.write(sql)


def write_gpt_queries(dest_dir: str, lines: list[str], postfix: str = ".sql"):
    """
    Writes the queries to files.

    Args:
        dest_dir (str): The directory to write the SQL files to.
        lines (list[str]): The list of query lines.
        postfix (str): The file extension to use.
    """
    lines = [line for line in lines if line]

    log.info(f"Writing {len(lines)} queries to files in `{dest_dir}`")
    with log.progress("Writing queries", total=len(lines)) as progress:
        for i, line in enumerate(lines):
            progress.advance()

            response = json.loads(line)
            sql = response["response"]["body"]["choices"][0]["message"]["content"]
            id = response["custom_id"]

            write_query_to_file(sql, dest_dir, id, postfix)


def main():
    """
    Main function to generate SQL queries based on the provided prompt and dataset.
    """
    log.header("Generate SQL Queries")

    # Parse command line arguments
    argparser = argparse.ArgumentParser()
    argparser.add_argument("dataset", help="Dataset of the benchmark")
    argparser.add_argument("version", help="Version of the benchmark")
    argparser.add_argument("prompt", help="Prompt to use for generating queries for a benchmark")
    argparser.add_argument("-b", "--batch_output_file", help="Batch output file in case an error occurred", default=None)
    argparser.add_argument("-y", "--yes", help="Skip confirmation prompts", action="store_true", default=False)
    args = argparser.parse_args()

    prompt_file = os.path.join("prompts", args.version, args.prompt + ".yaml")
    dataset_file = os.path.join("prompts", args.dataset + ".yaml")
    dest_dir = os.path.join(args.version, args.dataset, "queries_generated")

    # Check if the prompt and dataset files exist
    if not os.path.exists(prompt_file):
        raise Exception(f"Prompt file {prompt_file} does not exist")
    if not os.path.exists(dataset_file):
        raise Exception(f"Dataset file {dataset_file} does not exist")

    # Create the destination directory if it doesn't exist
    if not os.path.exists(dest_dir):
        os.makedirs(dest_dir)

    # Load the prompt and dataset files
    with open(prompt_file, 'r') as f:
        prompt = yaml.safe_load(f)
    with open(dataset_file, 'r') as f:
        dataset = yaml.safe_load(f)

    # Validate the prompt and dataset files
    for attr in ["prompt", ["model", "models"], "count", "base_id"]:
        if not isinstance(attr, list):
            attr = [attr]
        if not any(a in prompt for a in attr):
            raise Exception(f"Prompt file {prompt_file} does not contain any of the attributes '{', '.join(attr)}'")

    if "schema" not in dataset:
        raise Exception(f"Dataset file {dataset_file} does not contain attribute 'schema'")

    models = prompt["model"] if isinstance(prompt["model"], list) else [prompt["model"]]
    temperatures = prompt["temperature"] if "temperature" in prompt and isinstance(prompt["temperature"], list) else [prompt.get("temperature", 1.0)]
    max_tokens = prompt.get("max_tokens", 4096)
    reasonings = prompt["reasoning"] if "reasoning" in prompt and isinstance(prompt["reasoning"], list) else [prompt.get("reasoning", None)]
    count = prompt["count"]
    base_id = prompt["base_id"]
    prompt_text = prompt["prompt"] + " " + dataset["schema"]
    limit = prompt.get("limit", count)

    def query_info(id, model, temperature, reasoning, input_tokens=None, output_tokens=None):
        return {
            "query": f"{id}.sql",
            "dataset": args.dataset,
            "version": args.version,
            "prompt": args.prompt,
            "model": model,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "reasoning": reasoning,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        }

    def compare_query_info(a, b):
        keys_to_compare = ["query", "dataset", "version", "prompt", "model", "temperature", "max_tokens", "reasoning"]
        for key in keys_to_compare:
            if a.get(key) != b.get(key):
                return False
        return True

    async def generate_queries_for_model(base_id_offset, model, temperature, reasoning):
        # Create a lock file and only proceed if it does not exist
        lock_file = os.path.join(dest_dir, f"{base_id_offset}.lock")
        if os.path.exists(lock_file):
            log.info(f"Lock file {lock_file} exists. Skipping generation for queries {base_id_offset} to {base_id_offset + limit - 1}.", model)
            log.newline()
            return

        try:
            with open(lock_file, "w") as lf:
                lf.write("locked\n")

            def callback(id: str, sql: str, input_tokens: int, output_tokens: int):
                comment = f"-- {json.dumps(query_info(id, model, temperature, reasoning, input_tokens, output_tokens))} \n"
                write_query_to_file(sql, dest_dir, id, comment=comment)

            ids = []
            for i in range(base_id_offset, base_id_offset + limit):
                exists = os.path.exists(os.path.join(dest_dir, f"{i}.sql"))
                if exists:
                    with open(os.path.join(dest_dir, f"{i}.sql"), "r") as f:
                        exists = False
                        comment = f.readline()
                        if comment.startswith("-- "):
                            try:
                                info = json.loads(comment.removeprefix("-- ").strip())
                                exists = compare_query_info(query_info(i, model, temperature, reasoning), info)
                            except:
                                pass
                if not exists:
                    ids.append(i)

            if len(ids) == 0:
                log.info(f"All {limit} queries for model {model} already exist. Skipping generation.", model)
                log.newline()
                return

            log.info(f"Using {model} model for generating {limit} queries for {args.dataset} benchmark at version {args.version}", model)
            log.info(f"The generated queries will be saved in `{dest_dir}` in files `{base_id_offset}.sql` to `{base_id_offset + limit - 1}.sql`", model)
            if len(ids) != limit:
                log.info(f"Skipping {limit - len(ids)} queries for model {model} due to existing files. Generating {len(ids)} queries only.", model)

            await llm(model, len(ids), ids, prompt_text, callback, temperature=temperature, max_tokens=max_tokens, reasoning=reasoning, batch_output_file=args.batch_output_file, yes=args.yes)

            log.info(f"Generated {limit} queries for {args.dataset} benchmark at version {args.version} using {model} model", model)
            log.info(f"The generated queries are saved in `{dest_dir}` in files `{base_id_offset}.sql` to `{base_id_offset + limit - 1}.sql`", model)
        except Exception as e:
            log.error(f"Error generating queries: {e}", model)
            log.error(traceback.format_exc())
        finally:
            if os.path.exists(lock_file):
                os.remove(lock_file)

        log.newline()

    params = []
    for model in models:
        for temperature in temperatures:
            for reasoning in reasonings:
                params.append((base_id + len(params)*count, model, temperature, reasoning))

    # extract the key from the batch output file if it exists
    if args.batch_output_file:
        batched_id = None
        with open(args.batch_output_file, "r") as bf:
            for line in bf:
                response = json.loads(line)
                for id_name in ["custom_id"]:
                    if id_name in response:
                        try:
                            id = int(response[id_name])
                            batched_id = min(batched_id, id) if batched_id is not None else id
                        except:
                            continue

        if batched_id is None:
            raise Exception(f"Could not extract any valid id from batch output file {args.batch_output_file}")

        base_id_offset, model, temperature, reasoning = params[batched_id // count]
        log.info(f"Found batch from id {batched_id} for model {model}")
        asyncio.run(generate_queries_for_model(base_id_offset, model, temperature, reasoning))
    else:
        async def run_all_models():
            tasks = [generate_queries_for_model(base_id_offset, model, temperature, reasoning) for base_id_offset, model, temperature, reasoning in params]
            await asyncio.gather(*tasks)

        asyncio.run(run_all_models())


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log.error(e)
        log.error(traceback.format_exc())
        raise e
