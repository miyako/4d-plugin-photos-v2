#!/usr/bin/env python3
"""Use the identical harness for immutable baseline and current actual sources."""
from pathlib import Path
import io
import subprocess
import sys
import tarfile
import tempfile

root = Path(__file__).resolve().parents[2]
runner = Path(__file__).with_name("run.py")
baseline = "bfbed9ac1a3c4e7ecadb15132690e498a0fa416b"
with tempfile.TemporaryDirectory(prefix="photos-v2-baseline-") as directory:
    data = subprocess.check_output([
        "git", "archive", baseline, "--", "photos-v2/4D Plugin API",
        "photos-v2/4DPlugin.cpp", "photos-v2/4DPlugin.h", "photos-v2/manifest.json",
        "photos-v2/v11/4D Plugin API",
    ], cwd=root)
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        archive.extractall(directory, filter="data")
    subprocess.run([sys.executable, str(runner), directory, "--expect-baseline"], check=True)
subprocess.run([sys.executable, str(runner), str(root)], check=True)
