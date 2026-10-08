# Local LLMs on an AMD Ryzen AI laptop (WSL + Windows)

Serve an OpenAI-compatible LLM endpoint on `http://127.0.0.1:11435/v1` from this machine's
Radeon 860M iGPU (or CPU), several different ways, and chat with it through Open WebUI running
in a `wslc` container. Everything is driven by [mise](https://mise.jdx.dev) tasks; run
`mise tasks` for the live list.

**Hardware:** AMD Ryzen AI 7 PRO 350, Radeon 860M (gfx1152, RDNA 3.5, ~48 GiB shared memory), XDNA 2
NPU. **OS:** Windows 11 with WSL 2 (`networkingMode=Mirrored`), WSL containers (`wslc`).

## Quick start

```sh
mise run serve:gpu:vulkan-win   # fastest: gemma-4-26B on the GPU via native Windows llama.cpp (Vulkan)
mise run webui                  # then open http://localhost:3000 in Edge and pick the model
mise run serve:test             # optional: send a test chat to whatever is serving
mise run stop:all               # stop every server and the Open WebUI container
```

Only one `serve:*` task can run at a time, since they all use `SERVE_PORT` (11435).

## Tasks

### Serving

| Task | Model | Runs on | Status on this machine |
|---|---|---|---|
| `serve:cpu:llama` | Qwen3-0.6B (GGUF) | CPU, bundled llama-server in WSL | works |
| `serve:gpu:llama` | gemma-4-26B-A4B (GGUF Q4_K_M) | GPU, ROCm in WSL, bundled llama-server | works: ~5 min load, ~5 tok/s |
| `serve:gpu:rocm` | gemma-4-26B-A4B (GGUF Q4_K_M) | GPU, `rocm serve` + Lemonade | **fails**: rocm's 2-minute load limit (see below) |
| `serve:gpu:rocm:small` | Qwen3-0.6B (GGUF) | GPU, `rocm serve` + Lemonade | works |
| `serve:gpu:rocm:vllm` | Qwen/Qwen3-0.6B (safetensors) | GPU, `rocm serve` + vLLM | works: ~90 s start, ~29 tok/s; needs `vllm:build` and OpenMPI |
| `serve:gpu:vulkan-win` | gemma-4-26B-A4B (GGUF Q4_K_M) | GPU, native Windows `llama-server.exe` (Vulkan) | **works, fastest**: ~48 s load, ~11 tok/s |

Override the model for the GPU tasks with `GPU_MODEL`, e.g.
`GPU_MODEL=unsloth/Qwen3-0.6B-GGUF:Q4_K_M mise run serve:gpu:vulkan-win`.

Speeds are from a single 400-token generation (256 for `serve:gpu:llama`), so treat them as rough.

### Stopping

| Task | Stops |
|---|---|
| `serve:cpu:llama:stop` | the llama-server from `serve:cpu:llama` (matched by `--alias cpu-model`) |
| `serve:gpu:llama:stop` | the llama-server from `serve:gpu:llama` (matched by `--alias gpu-model`) |
| `serve:gpu:rocm:stop` | every `rocm serve` service (Lemonade or vLLM, any port), plus leftover `rocm serve` launchers |
| `serve:gpu:vulkan-win:stop` | the Windows `llama-server.exe` (matched by `--alias vulkan-model`) |
| `webui:stop` | the Open WebUI container (chat history stays in the `open-webui` volume) |
| `stop:all` | all of the above; safe to run when nothing is running |

Each stop task only touches its own server, so for example `serve:cpu:llama:stop` never kills
the llama-server that `rocm serve` launched from the same binary.

### Other

| Task | Does |
|---|---|
| `webui` | Open WebUI in a `wslc` container on http://localhost:3000, using whichever server is on `SERVE_PORT`; login disabled (`WEBUI_AUTH=False`, loopback only) |
| `serve:test` | chat completion against the first model the running server reports |
| `vllm:build` | builds vLLM from source for gfx1152 into `.vllm-gfx1152/` (~15 min, re-runnable) |
| `rocm` | the `rocm` CLI with a workspace-local `XDG_RUNTIME_DIR`, e.g. `mise run rocm -- services list` |

## How it fits together

```
 Edge ──► localhost:3000 ──► Open WebUI (wslc container)
                                   │  http://host.wslc.internal:11435/v1
                                   ▼
                      127.0.0.1:11435  (Windows loopback = WSL loopback, mirrored mode)
           ┌───────────────────────┼─────────────────────────┐
   llama-server (WSL)        rocm serve (WSL)        llama-server.exe (Windows)
   CPU, or ROCm via          Lemonade llama.cpp       Vulkan, AMD Windows driver
   /dev/dxg                  or vLLM, via /dev/dxg
```

- **Networking.** A `wslc` container runs in its own VM, so `localhost`, the bridge gateway, and
  `host.docker.internal` don't reach WSL. `host.wslc.internal` resolves to the host loopback, and
  with mirrored networking that's the same loopback WSL and Windows processes bind, so every
  server can stay on `127.0.0.1` and no firewall changes are needed.
- **Calling `wslc` from scripts.** `wslc` is a zsh alias; the scripts call `wslc.exe` directly.

## Findings

### `rocm serve` + Lemonade: hardcoded 2-minute load limit

rocm-cli waits a fixed 2 minutes for a Lemonade llama-server to answer `/v1/models`, then kills it
and marks the service `failed`
([`engines/lemonade/src/process.rs:542`](https://github.com/ROCm/rocm-cli/blob/a5e507a70939d6345a8a5047866d3df68147b359/engines/lemonade/src/process.rs#L535-L545),
`Duration::from_mins(2)`). There is no flag or environment variable to change it. gemma-4-26B
takes ~5 minutes to load on this GPU through ROCm in WSL, so `serve:gpu:rocm` always fails;
`serve:gpu:llama` runs the same bundled llama-server directly, with no limit.

### Running llama-server on the GPU yourself needs rocm's environment

Run bare, the bundled llama-server silently falls back to the CPU. `serve:gpu:llama` sets what
rocm sets for it: `ROCM_PATH` and `LD_LIBRARY_PATH` pointing at the bundled gfx1152 TheRock build
(`THEROCK_DIR` in `mise.toml`), plus `HIP_VISIBLE_DEVICES=0`.

### vLLM on WSL needed four fixes

rocm-cli's vLLM engine waits 5 minutes by default and the wait is configurable
(`ROCM_CLI_VLLM_READY_TIMEOUT_SECS`, set to 900). Getting vLLM 0.26 to run at all under WSL took:

1. **GPU detection: the `vllm-wsl/` plugin.** vLLM decides it's on ROCm only by asking amdsmi,
   which needs the amdgpu kernel driver; WSL exposes the GPU through `/dev/dxg` instead, so amdsmi
   fails with `AMDSMI_STATUS_DRIVER_NOT_LOADED` and vLLM reports "Failed to infer device type".
   `vllm-wsl/` is a vLLM platform plugin (entry point `vllm.platform_plugins`, enabled via
   `PYTHONPATH`) that, on WSL, answers vLLM's handful of amdsmi calls from torch's HIP device
   properties and hands vLLM its stock `RocmPlatform`.
2. **`UVA is not available`.** vLLM's V2 model runner needs pinned-memory UVA, which vLLM turns
   off on WSL. The task sets `VLLM_USE_V2_MODEL_RUNNER=0`.
3. **No gfx1152 kernels.** The vLLM wheel `rocm engines install vllm` installs has kernels for
   gfx1150/gfx1151 but not gfx1152 (`hipErrorInvalidDeviceFunction`).
   `HSA_OVERRIDE_GFX_VERSION` doesn't help under WSL: the Windows driver rejects code built for
   another chip (`hipErrorInvalidImage`). `mise run vllm:build` compiles vLLM for gfx1152; see below.
4. **Out of memory at startup.** On this iGPU vLLM sees all 47.7 GiB of shared memory, and its
   0.9 default reserved ~42 GiB of KV cache. The task passes `--gpu-memory-utilization 0.2`
   (via `VLLM_GPU_MEMORY_UTILIZATION`), which leaves ~7.7 GiB, about 72k tokens.

`serve:gpu:rocm:vllm` points rocm at the rebuilt vLLM with `ROCM_CLI_VLLM_PYTHON`. vLLM also needs
OpenMPI, which has to be installed once with sudo:

```sh
sudo apt-get update && sudo apt-get install -y openmpi-bin libopenmpi-dev
```

### `vllm:build`

`scripts/vllm-build.sh`:

1. creates `.vllm-gfx1152/`, a venv layered on rocm's managed runtime through a `.pth` file, so it
   reuses the runtime's torch 2.11.0+rocm7.14.1 and leaves the runtime untouched;
2. installs build tools and the matching `rocm-sdk-devel` (headers and CMake configs) from
   `https://repo.amd.com/rocm/whl-multi-arch`, and symlinks the runtime's `_rocm_sdk_core` and
   `_rocm_sdk_libraries` beside it, because the devel package's files are relative links into them;
3. shallow-clones vLLM `v0.26.0` into `.build/` and builds a wheel with
   `VLLM_TARGET_DEVICE=rocm PYTORCH_ROCM_ARCH=gfx1152` (log: `.build/vllm-build.log`);
4. installs the wheel into the venv and fails unless `_C.abi3.so` contains gfx1152 code objects.

Knobs: `VLLM_VERSION` (default `v0.26.0`; must match the runtime's torch), `VLLM_ROCM_ARCH`
(default `gfx1152`), `MAX_JOBS` (default 6; hipcc jobs need ~3-4 GB each).

### Native Windows Vulkan is the fastest GPU path here

`serve:gpu:vulkan-win` runs upstream llama.cpp's Windows Vulkan build
(`WIN_LLAMA_BUILD`, currently `b11514`) natively, launched from WSL through interop. On first run
it installs the release under `%LOCALAPPDATA%\llama-vulkan\` and copies the GGUF from `.models/` to
the Windows disk once, since a Windows process reading 16 GB over `\\wsl$` is slow. Same gemma file
as `serve:gpu:llama`: ~48 s to load vs ~295 s, and ~11 vs ~5 tok/s. The 48 s load came right after
the copy and may have hit the file cache; a cold start may be slower. Windows reports the process
holding ~23 GiB of GPU memory, confirming it runs on the Radeon.

### Windows ML (evaluated, not set up)

The [Oct 7, 2026 Windows ML post](https://devblogs.microsoft.com/foundry-on-windows/build-on-winml-oct-7-26/)
adds GGUF support and `WinMLServer.exe`, an OpenAI-compatible server. On this machine it isn't a
better GPU path yet:

- Windows ML ships only llama.cpp's CPU backend; GPU use needs a `ggml-vulkan.dll` you build
  yourself (Visual Studio, Vulkan SDK). That's the same llama.cpp Vulkan code `serve:gpu:vulkan-win`
  already runs.
- `WinMLServer` listens on loopback only, creates a new access key each start, and rejects requests
  whose `Host` header isn't a loopback address, so Open WebUI in a container would need a proxy.
- It's the only route to the NPU: the AMD Vitis AI execution provider is already installed
  (`WindowsWorkload.EP.AMD.VitisAI.1.8`), and WSL can't reach the NPU at all. Not tried yet.

## Layout

| Path | What |
|---|---|
| `mise.toml` | env (ports, model repos, runtime paths, pinned builds) and all tasks |
| `scripts/` | one script per task |
| `vllm-wsl/` | vLLM platform plugin that stands in for amdsmi under WSL |
| `.models/` | model downloads (`LLAMA_CACHE`, `HF_HOME`); `~/.cache/huggingface` is root-owned here |
| `.vllm-gfx1152/`, `.build/` | output of `vllm:build` (venv, vLLM source, wheels, build log) |
| `.run/` | workspace-local `XDG_RUNTIME_DIR` for the `rocm` CLI |
| `%LOCALAPPDATA%\llama-vulkan\` | Windows llama.cpp build and model copy for `serve:gpu:vulkan-win` |

## Troubleshooting

- **Open WebUI shows no models:** nothing is serving on 11435. Start a `serve:*` task; `mise run webui`
  warns when nothing is answering.
- **Something is still holding port 11435:** `mise run stop:all`.
- **A rocm service failed:** `mise run rocm -- services list --all`; each service's log is under
  `~/.rocm/services/`.
- **Logs:** Open WebUI `wslc.exe logs -f open-webui`; vLLM build `.build/vllm-build.log`.
