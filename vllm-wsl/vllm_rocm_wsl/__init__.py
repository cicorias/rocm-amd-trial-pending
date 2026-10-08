"""vLLM platform plugin for ROCm under WSL.

WSL exposes the AMD GPU through /dev/dxg (librocdxg), not the amdgpu kernel driver,
so amdsmi fails with AMDSMI_STATUS_DRIVER_NOT_LOADED. vLLM's ROCm platform asks
amdsmi to detect the GPU and to look up its arch, name, memory and topology, so it
never starts. HIP itself works, so this answers those amdsmi calls from torch's HIP
device properties, then hands vLLM its stock RocmPlatform.

Loaded through the `vllm.platform_plugins` entry point (see the .dist-info next to
this package); put this directory on PYTHONPATH to enable it.
"""
import os


def _patch_amdsmi() -> None:
    import amdsmi
    import torch

    # torch.cuda.device_count() itself asks amdsmi first, so count via HIP directly
    def hip_device_count():
        return torch._C._cuda_getDeviceCount()

    def props(handle):
        return torch.cuda.get_device_properties(handle)

    def asic_info(handle):
        p = props(handle)
        return {
            "target_graphics_version": p.gcnArchName.split(":")[0],
            "device_id": "",
            "market_name": p.name,
        }

    def no_numa(handle):
        # WSL gives no NUMA topology; vLLM treats this as "disable NUMA binding"
        raise amdsmi.AmdSmiException("NUMA node not available under WSL")

    patches = {
        "amdsmi_init": lambda *args, **kwargs: None,
        "amdsmi_shut_down": lambda *args, **kwargs: None,
        "amdsmi_get_processor_handles": lambda: list(range(hip_device_count())),
        "amdsmi_get_gpu_asic_info": asic_info,
        "amdsmi_get_gpu_memory_total": lambda handle, mem_type: props(handle).total_memory,
        "amdsmi_get_gpu_device_uuid": lambda handle: str(props(handle).uuid),
        # Only consulted for tensor parallel across GPUs; WSL exposes one
        "amdsmi_topo_get_link_type": lambda a, b: {"hops": 1, "type": 2},
        "amdsmi_topo_get_numa_node_number": no_numa,
    }
    for name, fn in patches.items():
        setattr(amdsmi, name, fn)


def register() -> str | None:
    if not os.path.exists("/dev/dxg"):
        return None
    import torch

    if torch.version.hip is None or torch._C._cuda_getDeviceCount() == 0:
        return None
    # Must run before vllm.platforms.rocm is imported: it binds these names at import
    _patch_amdsmi()
    return "vllm.platforms.rocm.RocmPlatform"
