
packer {
  required_plugins {
    windows-update = {
      version = "0.12.0"
      source = "github.com/rgl/windows-update"
    }
    chef = {
      version = " >= 1.0.0"      
      source  = "github.com/bdwyertech/chef"
    }
    hyperv = {
      version = " >= 1.1.0"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

variable "build_directory" {
  type    = string
  default = "../../builds"
}

variable "cpus" {
  type    = string
  default = "2"
}

variable "disk_size" {
  type    = string
  default = "40000"
}

variable "hyperv_switch" {
  type    = string
}

variable "iso_checksum" {
  type    = string
}

variable "iso_url" {
  type    = string
}

variable "windows_image_name" {
  type    = string
}

variable "memory" {
  type    = string
  default = "8192"
}
variable "template" {
  type    = string
}

variable "username" {
  type    = string
  default = "packer"
}


variable "password" {
  type    = string
  default = "MgP3?kh-@BkqKRvW"
}


variable "secondary_iso_path" {
  type    = string
}

source "hyperv-iso" "install" {
  boot_command       = ["aaaa<wait><wait><enter>"]
  boot_wait          = "1s"
  communicator       = "winrm"
  cpus               = "${var.cpus}"
  disk_size          = "${var.disk_size}"
  headless           = true
  enable_secure_boot = true
  enable_tpm         = true
  generation         = "2"
  configuration_version = "9.0"
  iso_checksum       = "${var.iso_checksum}"
  iso_url            = "${var.iso_url}"
  memory             = "${var.memory}"
  output_directory   = "${var.build_directory}/${var.template}-stage0"
  shutdown_command   = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -ExecutionPolicy Bypass c:\\windows\\temp\\sysprep.ps1"
  shutdown_timeout   = "20m"
  winrm_username     = "${var.username}"
  winrm_password     = "${var.password}"
  winrm_timeout      = "1h"
  switch_name        = "${var.hyperv_switch}"
  vm_name            = "${var.template}"
  secondary_iso_images = [ "${var.secondary_iso_path}" ]
}

build {
  sources = ["source.hyperv-iso.install"]

  provisioner "chef-solo" {
    cookbook_paths = ["${path.root}/cookbooks"]
    guest_os_type  = "windows"
    run_list       = ["packer::first_boot"]
    version        = 17
  }

  provisioner "windows-restart" {
  }

  # run 4 times to ensure that all updates are installed
  provisioner "windows-update" {}

  provisioner "windows-restart" {}

  provisioner "windows-update" {}
  
  provisioner "windows-restart" {}

  provisioner "windows-update" {}
  
  provisioner "windows-restart" {}

  provisioner "windows-update" {}
  
  provisioner "windows-restart" {}


  provisioner "chef-solo" {
    cookbook_paths = ["${path.root}/cookbooks"]
    guest_os_type  = "windows"
    run_list       = ["packer::finalize"]
    version        = 17
  }
  
  provisioner "powershell" {
    elevated_password = "${var.password}"
    elevated_user     = "${var.username}"
    script            = "${path.root}/scripts/prepare_sysprep.ps1"
  }

  provisioner "windows-restart" {}
  
  /*
  this script is embedded in prepare_sysprep.ps1 
  uncomment this block if you would like to see script output for diagnostics
  provisioner "powershell" {
    elevated_password = "${var.password}"
    elevated_user     = "${var.username}"
    script            = "${path.root}/scripts/sysprep.ps1"
    timeout           = "5m"

  } */
  }
