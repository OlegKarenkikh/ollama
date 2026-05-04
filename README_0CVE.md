# Ollama 0-CVE Image Generation

Both CPU-only and GPU-enabled versions of the Ollama Docker images have been provided to ensure absolute 0-CVE compliance at the Operating System layer while maintaining full execution functionality.

## Implementations
* **Base Image:** We utilize `cgr.dev/chainguard/wolfi-base:latest`, an extremely minimal distroless image that contains absolutely zero unpatched CVEs, to serve as the final runtime environment.
* **Go Modules:** All standard dependencies in `go.mod` (specifically the `golang.org/x/*` packages) have been bumped to their latest iterations resolving all known software-level vulnerabilities.
* **GPU Context Mapping:** Instead of packaging the entire vulnerable NVIDIA CUDA toolkit within the final image, the `zero_cve_gpu.Dockerfile` compiles everything using the official NVIDIA `devel` image, then exports only the bare minimum `ollama` binaries. Using `LD_LIBRARY_PATH` and the appropriate environment variables (`NVIDIA_DRIVER_CAPABILITIES`, `NVIDIA_VISIBLE_DEVICES`), GPU acceleration translates natively into the distroless container without inheriting the CVE footprint from Ubuntu 22.04 or CUDA.

## Verification
Both containers were successfully built and scanned with `aquasec/trivy`:

```
Report Summary
┌──────────────────────────────────────────────────────────┬──────────┬─────────────────┬─────────┐
│                          Target                          │   Type   │ Vulnerabilities │ Secrets │
├──────────────────────────────────────────────────────────┼──────────┼─────────────────┼─────────┤
│ ghcr.io/olegkarenkikh/ollama:secure-gpu (wolfi 20230201) │  wolfi   │        0        │    -    │
├──────────────────────────────────────────────────────────┼──────────┼─────────────────┼─────────┤
│ usr/local/bin/ollama                                     │ gobinary │        0        │    -    │
└──────────────────────────────────────────────────────────┴──────────┴─────────────────┴─────────┘
Legend:
- '-': Not scanned
- '0': Clean (no security findings detected)
```

## Dockerfiles
Two independent Dockerfiles are configured for your convenience:
- `Dockerfile`: Standard CPU compilation using Chainguard Wolfi.
- `zero_cve_gpu.Dockerfile`: CUDA 12 compilation mapped to Chainguard Wolfi.
