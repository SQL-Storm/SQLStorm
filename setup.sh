#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

pushd "$SCRIPT_DIR" || exit 1

# Initialize the virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install the dependencies
pip3 install -r requirements.txt --upgrade

popd

# Keep the virtual environment activated
exec "$SHELL"