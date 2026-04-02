#!/bin/bash
# Fast deploy — skips gradle JAR rebuild.
# Copies shaders + DLL directly to the extracted radiance/ folder.
# Use this for shader and C++ changes. Only run full_deploy.sh for Java/YAML changes.

set -e
MCVR="d:/Projects/Minecraft Shaders/MCVR"
RADIANCE_RES="d:/Projects/Minecraft Shaders/Radiance/src/main/resources"
GAME_RADIANCE="c:/Users/Konstantin Victoria/AppData/Roaming/ModrinthApp/profiles/Fabric 1.21.4/radiance"

echo "=== Building shaders ==="
cd "$MCVR" && cmake --build build --target shaders 2>&1 | tail -3

echo "=== Building core (Release) ==="
cmake --build build --target core --config Release 2>&1 | tail -3

echo "=== Copying DLL ==="
cp "$MCVR/build/src/core/Release/core.dll" "$GAME_RADIANCE/core.dll"

echo "=== Copying SPV shaders ==="
cp -r "$MCVR/build/src/shader/shaders/"* "$GAME_RADIANCE/shaders/"

echo "=== Copying internal.zip (RT shaders) ==="
cmake --install build 2>&1 | tail -1
cp "$RADIANCE_RES/shaders/world/ray_tracing/internal.zip" "$GAME_RADIANCE/shaders/world/ray_tracing/internal.zip" 2>/dev/null || true

echo "=== FAST DEPLOY COMPLETE ==="
