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

source "hyperv-vmcx" "repack" {
  clone_from_vmcx_path = "${var.export_path}"
  copy_in_compare      = false
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
}

build {
  sources = ["source.hyperv-vmcx.repack"]

  # Run cleanup scripts including cloud-init reset
  provisioner "shell" {
    execute_command   = "echo '${var.password}' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
    expect_disconnect = true
    scripts = var.minimal_cleanup ? [
      "${path.root}/scripts/cloud-init-reset.sh",
      "${path.root}/scripts/cleanup.sh"
    ] : [
      "${path.root}/scripts/cloud-init-reset.sh",
      "${path.root}/scripts/cleanup.sh",
      "${path.root}/../linux/scripts/minimize.sh"
    ]
  }
}