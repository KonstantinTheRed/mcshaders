#!/usr/bin/env python3
"""
compile_shaders.py — Compile all GLSL shaders to SPIR-V using glslc.

Usage:
    python compile_shaders.py            # compile all shaders
    python compile_shaders.py --clean    # remove all .spv files
    python compile_shaders.py --verbose  # show full glslc commands

Searches for glslc in: VULKAN_SDK env var, PATH, common install locations.
Outputs .spv files alongside source files in shaders/compiled/
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

# Project root
ROOT = Path(__file__).parent
SHADERS_DIR = ROOT / "shaders"
OUTPUT_DIR = ROOT / "shaders" / "compiled"
INCLUDE_DIR = SHADERS_DIR / "include"

# Shader file extensions and their glslc stage flags
SHADER_STAGES = {
    ".comp": "compute",
    ".vert": "vertex",
    ".frag": "fragment",
    ".rgen": "rgen",
    ".rchit": "rchit",
    ".rmiss": "rmiss",
    ".rahit": "rahit",
    ".rint": "rint",
    ".rcall": "rcall",
}

# glslc flags
COMMON_FLAGS = [
    "--target-env=vulkan1.3",
    "--target-spv=spv1.6",
    f"-I{INCLUDE_DIR}",
    "-O",  # optimize
]


def find_glslc():
    """Find glslc compiler."""
    # 1. Check VULKAN_SDK
    sdk = os.environ.get("VULKAN_SDK", "")
    if sdk:
        candidate = Path(sdk) / "Bin" / "glslc.exe"
        if candidate.exists():
            return str(candidate)

    # 2. Check PATH
    found = shutil.which("glslc")
    if found:
        return found

    # 3. Scan common Windows install locations
    vulkan_base = Path("C:/VulkanSDK")
    if vulkan_base.exists():
        versions = sorted(vulkan_base.iterdir(), reverse=True)
        for v in versions:
            candidate = v / "Bin" / "glslc.exe"
            if candidate.exists():
                return str(candidate)

    return None


def collect_shaders():
    """Find all shader source files to compile."""
    shaders = []
    for ext in SHADER_STAGES:
        shaders.extend(SHADERS_DIR.rglob(f"*{ext}"))
    return sorted(shaders)


def compile_shader(glslc, src, verbose):
    """Compile a single shader file. Returns (path, success, message)."""
    ext = src.suffix
    stage = SHADER_STAGES.get(ext)
    if not stage:
        return src, False, f"Unknown stage for extension {ext}"

    # Output path: shaders/compiled/<subdir>/<name>.spv
    rel = src.relative_to(SHADERS_DIR)
    out = OUTPUT_DIR / rel.with_suffix(rel.suffix + ".spv")
    out.parent.mkdir(parents=True, exist_ok=True)

    # Skip if output is newer than source
    if out.exists() and out.stat().st_mtime > src.stat().st_mtime:
        return src, True, "up to date"

    cmd = [
        glslc,
        f"-fshader-stage={stage}",
        *COMMON_FLAGS,
        str(src),
        "-o", str(out),
    ]

    if verbose:
        print(f"  $ {' '.join(cmd)}")

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            return src, False, result.stderr.strip()
        return src, True, "compiled"
    except subprocess.TimeoutExpired:
        return src, False, "compilation timed out"
    except Exception as e:
        return src, False, str(e)


def clean():
    """Remove all compiled .spv files."""
    if OUTPUT_DIR.exists():
        count = sum(1 for _ in OUTPUT_DIR.rglob("*.spv"))
        shutil.rmtree(OUTPUT_DIR)
        print(f"Cleaned {count} .spv files from {OUTPUT_DIR}")
    else:
        print("Nothing to clean.")


def main():
    verbose = "--verbose" in sys.argv or "-v" in sys.argv

    if "--clean" in sys.argv:
        clean()
        return

    print("=== Shader Compilation Pipeline ===\n")

    # Find compiler
    glslc = find_glslc()
    if not glslc:
        print("ERROR: glslc not found!\n")
        print("Install the Vulkan SDK:")
        print("  Option 1: Run setup_vulkan_sdk.ps1 (as admin)")
        print("  Option 2: Download from https://vulkan.lunarg.com/sdk/home#windows")
        print("  Option 3: Set VULKAN_SDK environment variable to your SDK path")
        sys.exit(1)

    print(f"Compiler: {glslc}")

    # Get version
    try:
        ver = subprocess.run([glslc, "--version"], capture_output=True, text=True)
        print(f"Version:  {ver.stdout.strip().split(chr(10))[0]}")
    except Exception:
        pass

    # Collect shaders
    shaders = collect_shaders()
    if not shaders:
        print("\nNo shader files found!")
        sys.exit(1)

    print(f"Shaders:  {len(shaders)} files\n")

    # Compile in parallel
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    success_count = 0
    skip_count = 0
    fail_count = 0
    errors = []

    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as executor:
        futures = {
            executor.submit(compile_shader, glslc, s, verbose): s
            for s in shaders
        }

        for future in as_completed(futures):
            src, ok, msg = future.result()
            rel = src.relative_to(SHADERS_DIR)

            if ok:
                if msg == "up to date":
                    skip_count += 1
                    if verbose:
                        print(f"  SKIP  {rel}")
                else:
                    success_count += 1
                    print(f"  OK    {rel}")
            else:
                fail_count += 1
                print(f"  FAIL  {rel}")
                errors.append((rel, msg))

    # Summary
    print(f"\n{'='*40}")
    print(f"Compiled: {success_count}  Skipped: {skip_count}  Failed: {fail_count}")

    if errors:
        print(f"\n--- Errors ---")
        for rel, msg in errors:
            print(f"\n{rel}:")
            for line in msg.split("\n"):
                print(f"  {line}")
        sys.exit(1)
    else:
        print("\nAll shaders compiled successfully!")
        print(f"SPIR-V output: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
