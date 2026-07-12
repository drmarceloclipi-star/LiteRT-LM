# Jourmingo LiteRT-LM Compatibility Fork

Apache-2.0 licensing is retained from the upstream project.

- Upstream: https://github.com/google-ai-edge/LiteRT-LM
- Upstream base: `v0.12.0` (`ffed38adbc33509480b5340e5173638bc20a68ff`)
- Upstream XCFramework: https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.12.0/CLiteRTLM.xcframework.zip
- Upstream XCFramework checksum: `3c2a11ecc8511d1e74efa7ca308dc7130c95223325c33212337ffb0563b79cde`

## Compatibility changes

1. `Package.swift` is an iOS-only Swift Package shim that downloads the upstream `CLiteRTLM` XCFramework from its release URL.
2. Removed all repository prebuilt-library LFS payloads; the package does not use them.
3. Removed LiteRTLM's package-level unsafe `-all_load` linker setting.

Purpose: provide a controlled, reproducible Swift Package dependency for Jourmingo's iOS integration. Jourmingo applies `-all_load` only in its app target build settings.
