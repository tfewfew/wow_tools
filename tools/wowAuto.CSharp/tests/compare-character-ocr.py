"""Compare legacy and C# character creation using saved images and the same Python environment."""
from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
import ctypes
from ctypes import wintypes
import io
import json
import msvcrt
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageChops


TOOL_ROOT = Path(__file__).resolve().parents[1]
LEGACY_BRIDGE = TOOL_ROOT.parent / "wowAuto" / "character-create" / "bridge.py"
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".bmp", ".webp"}


def pipe_server_pid():
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    process_id_to_session_id = kernel.ProcessIdToSessionId
    process_id_to_session_id.argtypes = (wintypes.DWORD, ctypes.POINTER(wintypes.DWORD))
    process_id_to_session_id.restype = wintypes.BOOL
    session = wintypes.DWORD()
    if not process_id_to_session_id(os.getpid(), ctypes.byref(session)):
        raise ctypes.WinError(ctypes.get_last_error())

    server_process_id = kernel.GetNamedPipeServerProcessId
    server_process_id.argtypes = (wintypes.HANDLE, ctypes.POINTER(wintypes.ULONG))
    server_process_id.restype = wintypes.BOOL
    pid = wintypes.ULONG()
    try:
        with open(fr"\\.\pipe\wowauto-csharp-v1-{session.value}", "r+b", buffering=0) as pipe:
            if not server_process_id(msvcrt.get_osfhandle(pipe.fileno()), ctypes.byref(pid)):
                raise ctypes.WinError(ctypes.get_last_error())
    except FileNotFoundError:
        return None
    return pid.value


def cli_request(cli, *args):
    result = subprocess.run(
        [str(cli), "--json", *map(str, args)], capture_output=True, encoding="utf-8",
        creationflags=subprocess.CREATE_NO_WINDOW, timeout=45, check=False,
    )
    reply = json.loads(result.stdout) if result.stdout.strip() else {}
    if result.returncode:
        raise RuntimeError(reply.get("error") or result.stderr.strip() or f"CLI exited {result.returncode}")
    return reply


@contextmanager
def desktop_host(exe, cli, data_root):
    if pipe_server_pid() is not None:
        raise RuntimeError("Close the running C# wowAuto before starting the isolated comparison.")

    data_root.mkdir()
    (data_root / "settings.json").write_text('{"ScreenshotKey":""}', encoding="utf-8")
    env = {**os.environ, "WOWAUTO_CHARACTER_PYTHON": sys.executable}
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    desktop = subprocess.Popen(
        [str(exe), "--data-root", str(data_root)], env=env, startupinfo=startup,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.monotonic() + 10
        while pipe_server_pid() != desktop.pid:
            if desktop.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError("The isolated C# wowAuto did not open its command pipe.")
            time.sleep(0.1)
        yield desktop.pid
    finally:
        if desktop.poll() is None:
            try:
                if pipe_server_pid() == desktop.pid:
                    cli_request(cli, "runtime", "close")
                    desktop.wait(timeout=10)
            finally:
                if desktop.poll() is None:
                    desktop.kill()
                    desktop.wait(timeout=5)


def legacy_preview(image):
    # Keep stdin open until the preview finishes. The legacy worker treats EOF as a stop request.
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        worker = subprocess.Popen(
            [sys.executable, "-B", "-u", str(LEGACY_BRIDGE)], cwd=LEGACY_BRIDGE.parent,
            stdin=subprocess.PIPE, stdout=output, stderr=errors, creationflags=subprocess.CREATE_NO_WINDOW,
            env={**os.environ, "PYTHONIOENCODING": "utf-8"},
        )
        try:
            worker.stdin.write((json.dumps({"mode": "preview", "image": str(image)}) + "\n").encode("utf-8"))
            worker.stdin.flush()
            exit_code = worker.wait(timeout=45)
        finally:
            if worker.poll() is None:
                worker.kill()
                worker.wait(timeout=5)
            worker.stdin.close()

        output.seek(0)
        preview = None
        for line in output:
            message = json.loads(line)
            if message["kind"] in {"operation", "error"}:
                raise RuntimeError(message.get("text") or "The legacy file preview requested a game operation.")
            if message["kind"] == "preview":
                preview = message
        if exit_code or preview is None:
            errors.seek(0)
            raise RuntimeError(errors.read().decode("utf-8", errors="replace") or "The legacy worker returned no preview.")
        return preview


def image_files(entries):
    images = set()
    for entry in entries:
        path = entry.resolve(strict=True)
        candidates = path.iterdir() if path.is_dir() else (path,)
        images.update(item for item in candidates if item.is_file() and item.suffix.lower() in IMAGE_SUFFIXES)
    if not images:
        raise ValueError("Pass at least one saved screenshot or directory containing images.")
    return sorted(images)


def compare(image, cli, desktop_pid, output):
    legacy = legacy_preview(image)
    if pipe_server_pid() != desktop_pid:
        raise RuntimeError("The isolated C# wowAuto changed during the comparison.")
    reply = cli_request(cli, "character", "preview", "--image", image, "--output", output)
    if reply["state"] != "completed":
        raise AssertionError(f"{image.name}: C# preview did not complete.")
    state = reply["data"]["state"]
    if state["message"] != legacy["description"]:
        raise AssertionError(f"{image.name}: button verdict differs. Legacy {legacy['description']!r}, C# {state['message']!r}.")
    new_hits = [(hit["text"], hit["score"]) for hit in state["hits"]]
    old_hits = [(hit["text"], hit["score"]) for hit in legacy["hits"]]
    if new_hits != old_hits:
        raise AssertionError(f"{image.name}: OCR text, order or confidence differs.")
    with Image.open(image) as source, Image.open(io.BytesIO(base64.b64decode(legacy["png"], validate=True))) as old, Image.open(output) as new:
        if new.format != "PNG" or source.size != old.size or old.size != new.size:
            raise AssertionError(f"{image.name}: preview dimensions or PNG format differ.")
        if ImageChops.difference(old.convert("RGB"), new.convert("RGB")).getbbox() is not None:
            raise AssertionError(f"{image.name}: annotated preview pixels differ.")
        dimensions = f"{source.width}×{source.height}"
    print(f"PASS {image.name} · {dimensions} · {len(new_hits)} OCR hits · {legacy['description']}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("screenshots", nargs="+", type=Path, help="Saved image files or directories of saved images.")
    parser.add_argument("--publish-root", type=Path, default=TOOL_ROOT / "publish")
    args = parser.parse_args()
    images = image_files(args.screenshots)
    publish = args.publish_root.resolve(strict=True)
    exe = (publish / "Desktop" / "WowAuto.exe").resolve(strict=True)
    cli = (publish / "Cli" / "wowauto-cli.exe").resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="wowauto-ocr-parity-") as temporary:
        root = Path(temporary)
        with desktop_host(exe, cli, root / "profile") as desktop_pid:
            for index, image in enumerate(images):
                compare(image, cli, desktop_pid, root / f"preview-{index}.png")
    print(f"PASS {len(images)} saved images match the legacy script.")


if __name__ == "__main__":
    main()
