packer {
  required_plugins {
    chef = {
      version = " >= 1.0.0"      
      source  = "github.com/bdwyertech/chef"
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
  default     = "Administrator"
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
  description = "Perform only minimal cleanup (skip defrag, etc.)"
}

variable "build_directory" {
  type    = string
  default = "../../builds"
}

variable "memory" {
  type        = number
  default     = 4096
  description = "Memory in MB for the VM during repack build"
}

variable "cpus" {
  type        = number
  default     = 2
  description = "Number of CPUs for the VM during repack build"
}

source "hyperv-vmcx" "repack" {
  clone_from_vmcx_path = "${var.export_path}"
  copy_in_compare      = false
  communicator         = "winrm"
  winrm_username       = "${var.username}"
  winrm_password       = "${var.password}"
  winrm_timeout        = "1h"
  switch_name          = "${var.hyperv_switch}"
  vm_name              = "${var.output_name}"
  output_directory     = "${var.build_directory}/${var.output_name}-stage0"
  shutdown_command     = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -ExecutionPolicy Bypass c:\\windows\\temp\\sysprep.ps1"
  shutdown_timeout     = "20m"
  headless             = true
  memory               = var.memory
  cpus                 = var.cpus

  # DO NOT set enable_secure_boot or enable_tpm here
  # The hyperv-vmcx builder inherits these settings from the source VM
  # Setting them explicitly causes errors when TPM is already initialized:
  # "Cannot modify the secure boot template ID property after the virtual TPM is initialized"
}

build {
  sources = ["source.hyperv-vmcx.repack"]

  # Run cleanup recipes based on minimal_cleanup flag
  # Packer's chef-solo provisioner automatically installs Chef if needed
  provisioner "chef-solo" {
    cookbook_paths = ["${path.root}/cookbooks"]
    guest_os_type  = "windows"
    run_list       = var.minimal_cleanup ? ["packer::minimal_repack"] : ["packer::repack"]
    version        = 17
  }
  
  # Prepare for sysprep (includes Chef uninstall)
  provisioner "powershell" {
    elevated_password = "${var.password}"
    elevated_user     = "${var.username}"
    script            = "${path.root}/scripts/prepare_sysprep.ps1"
  }

  provisioner "windows-restart" {
    restart_timeout = "10m"
  }

    //this script is embedded in prepare_sysprep.ps1 
  //uncomment this block if you would like to see script output for diagnostics

  /*
  provisioner "powershell" {
    elevated_password = "${var.password}"
    elevated_user     = "${var.username}"
    script            = "${path.root}/scripts/sysprep.ps1"
    timeout           = "15m"

  }
  */
  
}