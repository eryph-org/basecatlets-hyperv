
packer {
  required_plugins {
    windows-update = {
      version = "0.12.0"
      source = "github.com/rgl/windows-update"
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
  default = "4096"
}
variable "template" {
  type    = string
}

variable "username" {
  type    = string
  default = "Administrator"
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
  generation         = "2"
  iso_checksum       = "${var.iso_checksum}"
  iso_url            = "${var.iso_url}"
  memory             = "${var.memory}"
  output_directory   = "${var.build_directory}/${var.template}-stage0"
  shutdown_timeout   = "15m"
  winrm_username     = "${var.username}"
  winrm_password     = "${var.password}"
  winrm_timeout      = "12h"
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
  }

  provisioner "windows-restart" {
  }

  provisioner "windows-update" {}

  # run two times to ensure that all updates are installed
  provisioner "windows-update" {}
  

  # run vagrant optimization in vagrant build  
  provisioner "chef-solo" {
    only              = var.username == "vagrant" ? ["hyperv-iso.install"] : ["dummy"]
    cookbook_paths = ["${path.root}/cookbooks"]
    guest_os_type  = "windows"
    run_list       = ["packer::vagrant"]
  }

  provisioner "windows-restart" {
  }

  provisioner "chef-solo" {
    cookbook_paths = ["${path.root}/cookbooks"]
    guest_os_type  = "windows"
    run_list       = ["packer::finalize"]
  }

  provisioner "powershell" {
    elevated_password = "${var.password}"
    elevated_user     = "${var.username}"
    script            = "${path.root}/scripts/cleanup.ps1"
  }

}
