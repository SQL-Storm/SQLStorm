import asyncio
import json
import os
import concurrent.futures
import time
from tempfile import TemporaryDirectory
from typing import List

from openai import OpenAI
from anthropic import Anthropic
from google import genai
from google.genai import types
import boto3
import xai_sdk as xai
from botocore.config import Config

from log import log


async def openai_gpt(model: str, count: int, id: int | List[str], prompt: str | List[str], callback, temperature: float = 1.0, max_tokens: int = 1000, reasoning: str = "minimal", batch_output_file: str = None, yes: bool = False):
    """
    Process a batch of requests using OpenAI's GPT model.

    Args:
        model (str): The model to use for
        count (int): The number of requests.
        id (int | List[str]): The ID for the requests.
        prompt (str | List[str]): The prompt to use for requests.
        callback (callable): A callback function to handle the answered requests.
        temperature (float, optional): The temperature to use for the model. Default is 1.0.
        max_tokens (int, optional): The maximum number of tokens to generate. Default is 1000.
        batch_output_file (str, optional): The batch output file in case an error occurred.
    """
    gpt5_models = ["gpt-5-nano", "gpt-5-mini", "gpt-5", "gpt-5-pro"]

    token_limits = {
        "gpt-3.5-turbo": 4096,
    }
    if model in token_limits and max_tokens > token_limits[model]:
        log.warn(f"Model {model} only supports up to {token_limits[model]} max tokens, changing max_tokens from {max_tokens} to {token_limits[model]}", model)
        max_tokens = token_limits[model]

    gpt5 = model in gpt5_models
    if model == "gpt-5-pro" and reasoning != "high":
        log.warn(f"Model {model} only supports 'high' reasoning level, changing reasoning from '{reasoning}' to 'high'", model)
        reasoning = "high"

    def handler(lines):
        lines = [line for line in lines if line]

        input_tokens = 0
        output_tokens = 0

        log.info(f"Processing {len(lines)} responses", model)
        with log.progress("Processing", total=len(lines)) as progress:
            exception = None
            exception_response = None
            for line in lines:
                progress.advance()

                response = json.loads(line)
                try:
                    if gpt5:
                        content = None
                        for o in response["response"]["body"]["output"]:
                            if o["type"] == "message" and o["status"] == "completed":
                                content = o["content"][0]["text"]

                        if content is None:
                            raise Exception("Invalid response, could not find response message")
                            error_response = response
                            log.error(f"Response for id={response['custom_id']} does not contain a completed message:", model)

                        input_token = response["response"]["body"]["usage"]["input_tokens"]
                        output_token = response["response"]["body"]["usage"]["output_tokens"]
                    else:
                        content = response["response"]["body"]["choices"][0]["message"]["content"]
                        input_token = response["response"]["body"]["usage"]["prompt_tokens"]
                        output_token = response["response"]["body"]["usage"]["completion_tokens"]

                    input_tokens += input_token
                    output_tokens += output_token
                    callback(response["custom_id"], content, input_token, output_token)

                except Exception as e:
                    exception = e
                    exception_response = response
                    continue

            if exception:
                log.error(json.dumps(exception_response, indent=2), model)
                raise exception

        log.info(f"Processed {len(lines)} responses (input tokens: {input_tokens}, output tokens: {output_tokens})", model)

    if batch_output_file:
        with open(batch_output_file, 'r') as f:
            handler(f.readlines())
        return

    with TemporaryDirectory() as tempdir:
        input_file = os.path.join(tempdir, "input.jsonl")

        endpoint = "/v1/responses" if gpt5 else "/v1/chat/completions"

        def request(id, prompt): return {
            "custom_id": str(id),
            "method": "POST",
            "url": endpoint,
            "body": {
                "model": model,
                "temperature": temperature,
                "max_output_tokens": max_tokens,
                "reasoning": {"effort": reasoning},
                "instructions": "You are a SQL generator that cannot speak.",
                "input": prompt
            } if gpt5 else {
                "model": model,
                "temperature": temperature,
                "max_completion_tokens": max_tokens,
                "messages": [
                    {"role": "system", "content": "You are a SQL generator that cannot speak."},
                    {"role": "user", "content": prompt}
                ]
            }
        }

        # Create the input file
        with open(input_file, 'w') as f:
            for i in range(count):
                batch_json = request(id[i] if isinstance(id, list) else id + i, prompt[i] if isinstance(prompt, list) else prompt)
                f.write(json.dumps(batch_json) + "\n")

        log.info_verbose(f"Processing {count} requests with `{model}` using the following prompt:", model)
        log.info_verbose(json.dumps(batch_json, indent=2), model)
        if not yes:
            log.warn(f"Processing {count} requests with `{model}` will incur charges to your OpenAI account.", model)
            if not log.confirm("Do you want to continue?"):
                return

        log.info(f"Starting batch processing with `{model}` ...", model)
        start = time.time()

        # Create the batch
        client = OpenAI()
        batch_input_file = client.files.create(file=open(input_file, "rb"), purpose="batch")
        batch = client.batches.create(input_file_id=batch_input_file.id, endpoint=endpoint, completion_window="24h", metadata={"description": "1k"})
        log.info(f"{model} batch: {batch.id}", model)
        log.newline()

        # Wait for the batch to complete
        with log.progress(f"{model.upper():10}", count) as progress:
            await asyncio.sleep(10)

            while True:
                try:
                    result = client.batches.retrieve(batch.id)
                    progress.description(f"{model.upper():10} {result.status.capitalize()}")
                    if result.request_counts:
                        progress.completed(result.request_counts.completed)
                except Exception as e:
                    log.warn(str(e))

                if result.status == 'completed':
                    break
                if result.status == 'failed':
                    raise Exception(f"Batch {batch.id} failed: {result}")

                await asyncio.sleep(30)

        log.info(f"Batch {batch.id} completed in {int((time.time() - start) / 60)} minutes", model)

        # Download the output file
        file_response = client.files.content(result.output_file_id)

        # Write the output to a file
        handler(file_response.text.split('\n'))


async def google_llm(model: str, count: int, id: int | List[str], prompt: str | List[str], callback, temperature: float = 1.0, max_tokens: int = 1000, reasoning: str = "minimal", batch_output_file: str = None, yes: bool = False):
    """
    Process a batch of requests using Google's gemini model.

    Args:
        model (str): The model to use for
        count (int): The number of requests.
        id (int | List[str]): The ID for the requests.
        prompt (str | List[str]): The prompt to use for requests.
        callback (callable): A callback function to handle the answered requests.
        temperature (float, optional): The temperature to use for the model. Default is 1.0.
        max_tokens (int, optional): The maximum number of tokens to generate. Default is 1000.
        batch_output_file (str, optional): The batch output file in case an error occurred.
    """
    token_limits = {}
    if model in token_limits and max_tokens > token_limits[model]:
        log.warn(f"Model {model} only supports up to {token_limits[model]} max tokens, changing max_tokens from {max_tokens} to {token_limits[model]}", model)
        max_tokens = token_limits[model]

    def handler(lines):
        lines = [line for line in lines if line]

        input_tokens = 0
        output_tokens = 0

        log.info(f"Processing {len(lines)} responses", model)
        with log.progress("Processing", total=len(lines)) as progress:
            exception = None
            exception_response = None
            for line in lines:
                progress.advance()

                response = json.loads(line)
                try:
                    content = response["response"]["candidates"][0]["content"]["parts"][0]["text"]
                    input_token = response["response"]["usageMetadata"]["promptTokenCount"]
                    output_token = response["response"]["usageMetadata"]["candidatesTokenCount"]

                    input_tokens += input_token
                    output_tokens += output_token
                    callback(response["key"], content, input_token, output_token)
                except Exception as e:
                    exception = e
                    exception_response = response

            if exception:
                log.error(json.dumps(exception_response, indent=2), model)
                raise exception

        log.info(f"Processed {len(lines)} responses (input tokens: {input_tokens}, output tokens: {output_tokens})", model)

    if batch_output_file:
        with open(batch_output_file, 'r') as f:
            handler(f.readlines())
        return

    with TemporaryDirectory() as tempdir:
        input_file = os.path.join(tempdir, "input.jsonl")

        def request(id, prompt): return {
            "key": str(id),
            "request": {
                "model": f"models/{model}",
                "generation_config": {"temperature": temperature, "maxOutputTokens": max_tokens},
                "systemInstruction": {"parts": [{"text": "You are a SQL generator that cannot speak."}]},
                "contents": [{"parts":   [{"text": prompt}]}]
            }
        }

        # Create the input file
        with open(input_file, 'w') as f:
            for i in range(count):
                batch_json = request(id[i] if isinstance(id, list) else id + i, prompt[i] if isinstance(prompt, list) else prompt)
                f.write(json.dumps(batch_json) + "\n")

        log.info_verbose(f"Processing {count} requests with `{model}` using the following prompt:", model)
        log.info_verbose(json.dumps(batch_json, indent=2), model)
        if not yes:
            log.warn(f"Processing {count} requests with `{model}` will incur charges to your Google account.", model)
            if not log.confirm("Do you want to continue?"):
                return

        log.info(f"Starting batch processing with `{model}` ...", model)
        start = time.time()

        # Create the batch
        client = genai.Client()
        batch_input_file = client.files.upload(file=input_file, config=types.UploadFileConfig(display_name='input', mime_type='jsonl'))
        batch = client.batches.create(model=model, src=batch_input_file.name)
        log.info(f"Started batch: {batch.name}", model)
        log.newline()

        # Wait for the batch to complete
        with log.progress(f"{model.upper():10}", count) as progress:
            await asyncio.sleep(10)

            while True:
                try:
                    result = client.batches.get(name=batch.name)
                    state = result.state.name.replace("JOB_STATE_", "").lower()
                    progress.description(f"{model.upper():10} {state.capitalize()}")
                except Exception as e:
                    log.warn(str(e))

                if state == 'succeeded':
                    break
                elif state in ('failed', 'cancelled', 'expired'):
                    raise Exception(f"Batch {batch.name} failed: {result}")

                await asyncio.sleep(30)

        log.info(f"Batch {batch.name} completed in {int((time.time() - start) / 60)} minutes", model)

        if not result.dest and result.dest.file_name:
            raise Exception(f"Batch {batch.name} does not have a valid output file: {result}")

        # Results are in a file
        file_content = client.files.download(file=result.dest.file_name)
        # Process file_content (bytes) as needed
        response = file_content.decode('utf-8')

        # Write the output to a file
        handler(response.split('\n'))


async def claude_llm(model: str, count: int, id: int | List[str], prompt: str | List[str], callback, temperature: float = 1.0, max_tokens: int = 1000, reasoning: str = "minimal", batch_output_file: str = None, yes: bool = False):
    """
    Process a batch of requests using Anthropic's Claude model.

    Args:
        model (str): The model to use for
        count (int): The number of requests.
        id (int | List[str]): The ID for the requests.
        prompt (str | List[str]): The prompt to use for requests.
        callback (callable): A callback function to handle the answered requests.
        temperature (float, optional): The temperature to use for the model. Default is 1.0.
        max_tokens (int, optional): The maximum number of tokens to generate. Default is 1000.
        batch_output_file (str, optional): The batch output file in case an error occurred.
    """
    models = {
        "claude-3-haiku": "claude-3-haiku-20240307",
        "claude-3.5-haiku": "claude-3-5-haiku-20241022",
        "claude-4-sonnet": "claude-sonnet-4-20250514",
        "claude-4.5-sonnet": "claude-sonnet-4-5-20250929",
        "claude-4-opus": "claude-opus-4-20250514",
        "claude-4.1-opus": "claude-opus-4-1-20250805",
    }
    if model not in models:
        raise Exception(f"Model {model} not supported")

    token_limits = {
        "claude-3-haiku": 4096,
        "claude-3.5-haiku": 8192,
    }
    if model in token_limits and max_tokens > token_limits[model]:
        log.warn(f"Model {model} only supports up to {token_limits[model]} max tokens, changing max_tokens from {max_tokens} to {token_limits[model]}", model)
        max_tokens = token_limits[model]

    def handler(responses):
        input_tokens = 0
        output_tokens = 0

        log.info(f"Processing {len(responses)} responses", model)
        with log.progress("Processing", total=len(responses)) as progress:
            for response in responses:
                progress.advance()

                if isinstance(response, dict):
                    content = response["result"]["message"]["content"][0]["text"]
                    input_token = response["result"]["message"]["usage"]["input_tokens"]
                    output_token = response["result"]["message"]["usage"]["output_tokens"]
                    custom_id = response["custom_id"]
                else:
                    content = response.result.message.content[0].text
                    input_token = response.result.message.usage.input_tokens
                    output_token = response.result.message.usage.output_tokens
                    custom_id = response.custom_id

                input_tokens += input_token
                output_tokens += output_token
                callback(custom_id, content, input_token, output_token)
        log.info(f"Processed {len(responses)} responses (input tokens: {input_tokens}, output tokens: {output_tokens})", model)

    if batch_output_file:
        with open(batch_output_file, 'r') as f:
            handler([json.loads(line) for line in f.readlines()])
        return

    def request(id, prompt): return {
        "custom_id": str(id),
        "params": {
            "model": models[model],
            "temperature": temperature,
            "max_tokens": max_tokens,
            "system": "You are a SQL generator that cannot speak.",
            "messages": [{"role": "user", "content": prompt}]
        }
    }

    # Create the input file
    requests = []
    for i in range(count):
        batch_json = request(id[i] if isinstance(id, list) else id + i, prompt[i] if isinstance(prompt, list) else prompt)
        requests.append(batch_json)

    log.info_verbose(f"Processing {count} requests with `{model}` using the following prompt:", model)
    log.info_verbose(json.dumps(batch_json, indent=2), model)
    if not yes:
        log.warn(f"Processing {count} requests with `{model}` will incur charges to your Anthropic account.", model)
        if not log.confirm("Do you want to continue?"):
            return

    log.info(f"Starting batch processing with `{model}` ...", model)
    start = time.time()

    # Create the batch
    client = Anthropic()
    batch = client.messages.batches.create(requests=requests)
    log.info(f"{model} batch: {batch.id}", model)
    log.newline()

    # Wait for the batch to complete
    with log.progress(f"{model.upper():10}", count) as progress:
        await asyncio.sleep(10)

        while True:
            try:
                result = client.messages.batches.retrieve(batch.id)
                progress.description(f"{model.upper():10} {result.processing_status.capitalize()}")
            except Exception as e:
                log.warn(str(e))

            if result.request_counts:
                progress.completed(result.request_counts.succeeded)
                if (result.request_counts.errored + result.request_counts.canceled + result.request_counts.expired) > 0:
                    client.messages.batches.cancel(batch.id)
                    raise Exception(f"Batch {batch.id} failed: {result}")

            if result.processing_status == 'ended':
                break

            await asyncio.sleep(30)

    log.info(f"Batch {batch.id} completed in {int((time.time() - start) / 60)} minutes", model)

    # Download the output file
    response = client.messages.batches.results(batch.id)
    responses = [r for r in response]

    # Write the output to a file
    handler(responses)


async def bedrock_llm(model: str, count: int, id: int | list, prompt: str | list, callback, temperature: float = 1.0, max_tokens: int = 1000, reasoning: str = None, batch_output_file: str = None, yes: bool = False):
    """Invoke a Bedrock model for a batch of prompts.

    This performs synchronous per-prompt invocations using the Bedrock Runtime API.
    The `model` argument should be the Bedrock modelId (for example: "amazon.titan-rl" or a custom model id).
    """
    models = {
        # Anthropic Claude models
        "claude-3-haiku": "anthropic.claude-3-haiku-20240307-v1:0",
        "claude-3.5-haiku": "anthropic.claude-3-5-haiku-20241022-v1:0",
        "claude-4-sonnet": "anthropic.claude-sonnet-4-20250514-v1:0",
        "claude-4.5-sonnet": "anthropic.claude-sonnet-4-5-20250929-v1:0",
        "claude-4-opus": "anthropic.claude-opus-4-20250514-v1:0",
        "claude-4.1-opus": "anthropic.claude-opus-4-1-20250805-v1:0",
        # Amazon Nova models
        "nova-micro": "us.amazon.nova-micro-v1:0",
        "nova-lite": "us.amazon.nova-lite-v1:0",
        "nova-pro": "us.amazon.nova-pro-v1:0",
        "nova-premier": "us.amazon.nova-premier-v1:0",
        # OpenAI GPT OSS models
        "gpt-oss-20b": "openai.gpt-oss-20b-1:0",
        "gpt-oss-120b": "openai.gpt-oss-120b-1:0",
        # LLama models
        "llama-3.3-instruct": "us.meta.llama3-3-70b-instruct-v1:0",
        "llama-4-scout": "us.meta.llama4-scout-17b-instruct-v1:0",
        "llama-4-maverick": "us.meta.llama4-maverick-17b-instruct-v1:0",
        # Mistral models
        "pixtral-large": "us.mistral.pixtral-large-2502-v1:0",
        # DeepSeek models
        "deepseek-r1": "us.deepseek.r1-v1:0",
        # Qwen3 models
        "qwen3-coder": "qwen.qwen3-coder-30b-a3b-v1:0",
    }

    token_limits = {
        "nova-micro": 10000,
        "nova-lite": 10000,
        "nova-pro": 10000,
        "nova-premier": 10000,
        "llama-3.3-instruct": 8192,
    }
    if model in token_limits and max_tokens > token_limits[model]:
        log.warn(f"Model {model} only supports up to {token_limits[model]} max tokens, changing max_tokens from {max_tokens} to {token_limits[model]}", model)
        max_tokens = token_limits[model]

    if batch_output_file:
        raise Exception(f"Batch file not supported for Bedrock models ({model})")

    bedrock_client = boto3.client(service_name='bedrock-runtime', region_name="us-east-1", config=Config(connect_timeout=300, read_timeout=300))

    log.info(f"Processing {count} requests with `{model}`", model)
    if not yes:
        log.warn(f"Processing {count} requests with `{model}` will incur charges to your AWS account.", model)
        if not log.confirm("Do you want to continue?"):
            return
    log.newline()

    inference_config = {"temperature": temperature, "maxTokens": max_tokens}

    start = time.time()
    input_tokens = 0
    output_tokens = 0

    with log.progress(f"{model.upper():10}", count) as progress:

        def process_requests():
            nonlocal input_tokens, output_tokens
            for i in range(count):
                response = bedrock_client.converse(
                    modelId=models[model],
                    messages=[{
                        "role": "user",
                        "content": [{"text": prompt[i] if isinstance(prompt, list) else prompt}]
                    }],
                    system=[{"text": "You are a SQL generator that cannot speak."}],
                    inferenceConfig=inference_config)

                input_token = response['usage']['inputTokens']
                output_token = response['usage']['outputTokens']

                content = None
                for c in response['output']['message']["content"]:
                    if 'text' in c:
                        content = c['text']

                if content is None:
                    log.error(json.dumps(response, indent=2), model)
                    raise Exception(f"Could not find text content in response for model {model}!")

                input_tokens += input_token
                output_tokens += output_token
                callback(id[i] if isinstance(id, list) else id + i, content, input_token, output_token)

                progress.advance()

        loop = asyncio.get_running_loop()
        with concurrent.futures.ThreadPoolExecutor() as executor:
            await loop.run_in_executor(executor, process_requests)

    log.info(f"Processed {count} requests {int((time.time() - start) / 60)} minutes (input tokens: {input_tokens}, output tokens: {output_tokens})", model)


async def xai_llm(model: str, count: int, id: int | list, prompt: str | list, callback, temperature: float = 1.0, max_tokens: int = 1000, reasoning: str = None, batch_output_file: str = None, yes: bool = False):
    """Invoke a xAI model for a batch of prompts.

    This performs synchronous per-prompt invocations using the Bedrock Runtime API.
    The `model` argument should be the Bedrock modelId (for example: "amazon.titan-rl" or a custom model id).
    """
    if batch_output_file:
        raise Exception(f"Batch file not supported for Bedrock models ({model})")

    xai_client = xai.Client()

    log.info(f"Processing {count} requests with `{model}`", model)
    if not yes:
        log.warn(f"Processing {count} requests with `{model}` will incur charges to your AWS account.", model)
        if not log.confirm("Do you want to continue?"):
            return
    log.newline()

    start = time.time()
    input_tokens = 0
    output_tokens = 0

    with log.progress(f"{model.upper():10}", count) as progress:

        def process_requests():
            nonlocal input_tokens, output_tokens
            for i in range(count):
                chat = xai_client.chat.create(
                    model=model,
                    max_tokens=max_tokens,
                    temperature=temperature
                )
                chat.append(xai.chat.system("You are a SQL generator that cannot speak."))
                chat.append(xai.chat.user(prompt[i] if isinstance(prompt, list) else prompt))
                response = chat.sample()

                input_token = response.usage.prompt_tokens
                output_token = response.usage.completion_tokens
                content = response.content

                if content is None:
                    log.error(response, model)
                    raise Exception(f"Could not find text content in response for model {model}!")

                input_tokens += input_token
                output_tokens += output_token
                callback(id[i] if isinstance(id, list) else id + i, content, input_token, output_token)

                progress.advance()

        loop = asyncio.get_running_loop()
        with concurrent.futures.ThreadPoolExecutor() as executor:
            await loop.run_in_executor(executor, process_requests)

    log.info(f"Processed {count} requests {int((time.time() - start) / 60)} minutes (input tokens: {input_tokens}, output tokens: {output_tokens})", model)


async def openai_sync_llm(model: str, count: int, id: int | List[str], prompt: str | List[str], callback, temperature: float = 1.0, max_tokens: int = 1000, reasoning: str = None, batch_output_file: str = None, yes: bool = False):
    """Perform non-batched synchronous OpenAI calls for each prompt.

    This runs the synchronous client calls in a thread pool and invokes `callback(custom_id, content, input_tokens, output_tokens)`
    for each response.
    """
    if batch_output_file:
        raise Exception("Batch file not supported for synchronous OpenAI requests")

    if model == "codex-mini-latest" and reasoning == "minimal":
        log.warn(f"Model {model} does not supports 'minimal' reasoning level, changing reasoning from '{reasoning}' to 'low'", model)
        reasoning = "low"
    client = OpenAI()

    log.info(f"Processing {count} requests with `{model}` (sync) ...", model)
    if not yes:
        log.warn(f"Processing {count} requests with `{model}` will incur charges to your OpenAI account.", model)
        if not log.confirm("Do you want to continue?"):
            return
    log.newline()

    start = time.time()
    input_tokens = 0
    output_tokens = 0

    with log.progress(f"{model.upper():10}", count) as progress:

        def process_requests():
            nonlocal input_tokens, output_tokens
            for i in range(count):
                prompt_text = prompt[i] if isinstance(prompt, list) else prompt

                response = client.responses.create(model=model, input=prompt_text, temperature=temperature, max_output_tokens=max_tokens, reasoning={"effort": reasoning} if reasoning else None)

                content = None
                for o in response.output:
                    if o.type == "message" and o.status == "completed":
                        content = o.content[0].text

                if content is None:
                    raise Exception("Invalid response, could not find response message in {response}")

                input_token = response.usage.input_tokens
                output_token = response.usage.output_tokens

                input_tokens += input_token
                output_tokens += output_token
                callback(id[i] if isinstance(id, list) else id + i, content, input_token, output_token)

                progress.advance()

        loop = asyncio.get_running_loop()
        with concurrent.futures.ThreadPoolExecutor() as executor:
            await loop.run_in_executor(executor, process_requests)

    log.info(f"Processed {count} requests in {int((time.time() - start) / 60)} minutes (input tokens: {input_tokens}, output tokens: {output_tokens})", model)


async def llm(model: str, count: int, id: int | List[str], prompt: str | List[str], callback, temperature: float = 1.0, max_tokens: int = 1000, reasoning: str = None, batch_output_file: str = None, yes: bool = False):
    """
    Process a batch of requests using a LLM model.

    Args:
        model (str): The model to use for
        count (int): The number of requests.
        id (int | List[str]): The ID for the requests.
        prompt (str | List[str]): The prompt to use for requests.
        callback (callable): A callback function to handle the answered requests.
        temperature (float, optional): The temperature to use for the model. Default is 1.0.
        max_tokens (int, optional): The maximum number of tokens to generate. Default is 1000.
        batch_output_file (str, optional): The batch output file in case an error occurred.
    """
    # Check if the model is supported
    model_mapper = {
        # OpenAI GPT models
        "gpt-3.5-turbo": openai_gpt,
        "gpt-4o-mini": openai_gpt,
        "gpt-4o": openai_gpt,
        "gpt-4.1-nano": openai_gpt,
        "gpt-4.1-mini": openai_gpt,
        "gpt-4.1": openai_gpt,
        "gpt-5-nano": openai_gpt,
        "gpt-5-mini": openai_gpt,
        "gpt-5": openai_gpt,
        "gpt-5-pro": openai_gpt,
        "codex-mini-latest": openai_sync_llm,
        # Anthropic Claude models
        "claude-3-haiku": claude_llm,
        "claude-3.5-haiku": claude_llm,
        "claude-4-sonnet": claude_llm,
        "claude-4.5-sonnet": claude_llm,
        "claude-4-opus": claude_llm,
        "claude-4.1-opus": claude_llm,
        # Google Gemini models
        "gemini-2.5-flash-lite": google_llm,
        "gemini-2.5-flash": google_llm,
        "gemini-2.5-pro": google_llm,
        # Amazon Nova models
        "nova-micro": bedrock_llm,
        "nova-lite": bedrock_llm,
        "nova-pro": bedrock_llm,
        "nova-premier": bedrock_llm,
        # OpenAI GPT OSS models
        "gpt-oss-20b": bedrock_llm,
        "gpt-oss-120b": bedrock_llm,
        # LLama models
        "llama-3.3-instruct": bedrock_llm,
        "llama-4-scout": bedrock_llm,
        "llama-4-maverick": bedrock_llm,
        # Mistral models
        "pixtral-large": bedrock_llm,
        # DeepSeek models
        "deepseek-r1": bedrock_llm,
        # Qwen3 models
        "qwen3-coder": bedrock_llm,
        # xAI models
        "grok-4-fast-non-reasoning": xai_llm,
        "grok-code-fast": xai_llm,
        "grok-4": xai_llm,
    }
    if model not in model_mapper:
        raise Exception(f"Model '{model}' not supported")

    if count == 0:
        return

    await model_mapper[model](model, count, id, prompt, callback, temperature=temperature, max_tokens=max_tokens, reasoning=reasoning, batch_output_file=batch_output_file, yes=yes)
