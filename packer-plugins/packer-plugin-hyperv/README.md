# packer-plugin-hyperv (patched)

This directory holds source-level patches against `hashicorp/packer-plugin-hyperv`.
The built binary itself lives in `tools/plugins/github.com/hashicorp/hyperv/` and
is gitignored; this directory is the source of truth for what was changed and
how to rebuild it from a clean clone.

## Patches

| File                                       | Purpose                                                                                  |
|--------------------------------------------|------------------------------------------------------------------------------------------|
| `001-skip-secure-boot-on-clone.patch`      | Skip `SetVirtualMachineSecureBoot` for cloned Gen-2 VMs.                                 |

### 001-skip-secure-boot-on-clone

When `hyperv-vmcx` clones a Gen-2 VM, `StepCloneVM.Run` calls
`SetVirtualMachineSecureBoot` on the new VM. This fails on hosts where the
parent VM already has TPM initialized: the cloned VM inherits its secure-boot
settings from the parent and re-applying them throws an error. The patch
removes the call so cloned VMs keep the inherited security settings.

## Upstream base

- Repository: <https://github.com/hashicorp/packer-plugin-hyperv>
- Branch / commit: `main` at `51d0e41` ("Update PR template for PCI (#144)")
- Plugin version produced: `1.1.5-dev` (per `version/version.go`)

## Rebuild

```powershell
# 1. Clone upstream at the pinned commit
git clone https://github.com/hashicorp/packer-plugin-hyperv.git
cd packer-plugin-hyperv
git checkout 51d0e41

# 2. Apply each patch in order
git apply ..\hyperv-boxes\packer-plugins\packer-plugin-hyperv\001-skip-secure-boot-on-clone.patch

# 3. Build (requires Go matching plugin-dev/.go-version)
go build -o packer-plugin-hyperv_v1.1.5-dev_x5.0_windows_amd64.exe

# 4. Drop the binary into the repo's plugin directory
$dst = "..\hyperv-boxes\tools\plugins\github.com\hashicorp\hyperv"
Copy-Item packer-plugin-hyperv_v1.1.5-dev_x5.0_windows_amd64.exe $dst
(Get-FileHash $dst\packer-plugin-hyperv_v1.1.5-dev_x5.0_windows_amd64.exe -Algorithm SHA256).Hash.ToLower() `
  | Set-Content "$dst\packer-plugin-hyperv_v1.1.5-dev_x5.0_windows_amd64.exe_SHA256SUM"
```

`templates/windows/build.ps1` sets `PACKER_PLUGIN_PATH` to `tools/plugins/`,
so the rebuilt binary is picked up automatically by the next build.
