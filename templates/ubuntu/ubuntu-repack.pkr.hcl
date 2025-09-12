packer {
  required_plugins {
    hyperv = {
      version = " >= 1.1.0"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

variable "export_path" {
  type        = string
  description = "Path to exported Hyper-V VM directory"
}

variable "output_name" {
  type        = string
  description = "Name for the output VM"
}

variable "username" {
  type        = string
  description = "Username for VM access"
  default     = "packer"
}

variable "password" {
  type        = string
  description = "Password for VM access"
  sensitive   = true
}

variable "hyperv_switch" {
  type        = string
  description = "Hyper-V virtual switch to use"
}

variable "minimal_cleanup" {
  type        = bool
  default     = false
  description = "Perform only minimal cleanup"
}

variable "build_directory" {
  type    = string
  default = "../../builds"
}

variable "memory" {
  type        = number
  default     = 2048
  description = "Memory in MB for the VM during repack build"
}

variable "cpus" {
  type        = number
  default     = 2
  description = "Number of CPUs for the VM during repack build"
}

source "hyperv-vmcx" "repack" {
  clone_from_vmcx_path = "${var.export_path}"
  communicator         = "ssh"
  ssh_username         = "${var.username}"
  ssh_password         = "${var.password}"
  ssh_port             = 22
  ssh_timeout          = "10m"
  switch_name          = "${var.hyperv_switch}"
  vm_name              = "${var.output_name}"
  output_directory     = "${var.build_directory}/${var.output_name}-stage0"
  shutdown_command     = "echo '${var.password}' | sudo -S shutdown -P now"
  shutdown_timeout     = "5m"
  headless             = true
  memory               = var.memory
  cpus                 = var.cpus
}

build {
  sources = ["source.hyperv-vmcx.repack"]

  # Run cleanup scripts including cloud-init reset
  provisioner "shell" {
    execute_command   = "echo '${var.password}' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
    expect_disconnect = true
    scripts = var.minimal_cleanup ? [
      "${path.root}/scripts/azure.sh",
      "${path.root}/scripts/cloud-init-reset.sh",
      "${path.root}/scripts/cleanup.sh"
    ] : [
      "${path.root}/scripts/azure.sh",
      "${path.root}/scripts/cloud-init-reset.sh",
      "${path.root}/scripts/cleanup.sh",
      "${path.root}/../linux/scripts/minimize.sh"
    ]
  }
}

# For Linux/ubuntu, we create a symlink since both use the same template
# The repack.ps1 script looks for ubuntu-repack.pkr.hcl or linux-repack.pkr.hcl