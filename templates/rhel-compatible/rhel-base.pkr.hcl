packer {
  required_plugins {
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
  default = "4096"
}

variable "http_proxy" {
  type    = string
  default = "${env("http_proxy")}"
}

variable "https_proxy" {
  type    = string
  default = "${env("https_proxy")}"
}

variable "hyperv_switch" {
  type    = string
}

variable "iso_checksum" {
  type    = string
}

variable "iso_name" {
  type    = string
}

variable "iso_url" {
  type    = string
}

variable "memory" {
  type    = string
  default = "2048"
}

variable "no_proxy" {
  type    = string
  default = "${env("no_proxy")}"
}

variable "template" {
  type    = string
}

variable "distro_name" {
  type    = string
}

variable "username" {
  type    = string
  default = "packer"
}

# Generated via: echo 'packer' | openssl passwd -6 -stdin
variable "password_hash" {
  type    = string
  default = "$6$Z429xoUaiFrTT9TP$vemzmB.8Hbp7Fll4sDPe4U877taaO.hy8CieDqxJFs9F/4WmnXE.tTJl4xUQRc.CakFppjqRqsQ.WeEetPhIL."
}

variable "password" {
  type    = string
  default = "packer"
}

variable "hostname" {
  type    = string
  default = "rhel-compatible"
}

variable "boot_command" {
  type    = list(string)
  default = []
}

variable "boot_wait" {
  type    = string
  default = "10s"
}

variable "package_list" {
  type    = string
  default = ""
}

variable "kernel_packages" {
  type    = string
  default = "kernel"
}

variable "kernel_exclusions" {
  type    = string
  default = ""
}

variable "distro_specific_post" {
  type    = string
  default = ""
}

locals {
  http_directory = "${path.root}/http"
}

source "hyperv-iso" "install" {
  boot_command       = var.boot_command
  boot_wait          = var.boot_wait
  communicator       = "ssh"
  disk_block_size    = 1
  cpus               = var.cpus
  disk_size          = var.disk_size
  headless           = true
  enable_secure_boot = true
  secure_boot_template = "MicrosoftUEFICertificateAuthority"
  generation         = "2"
  configuration_version = "8.0"
  iso_checksum       = var.iso_checksum
  iso_url            = var.iso_url
  memory             = var.memory
  output_directory   = "${var.build_directory}/${var.template}-stage0"
  shutdown_command   = "echo '${var.password}' | sudo -S sh -c 'passwd -l ${var.username} && shutdown -P now'"
  ssh_password       = var.password
  ssh_port           = 22
  ssh_timeout        = "10000s"
  ssh_username       = var.username
  switch_name        = var.hyperv_switch
  vm_name            = var.template
  http_content = {
    "/ks.cfg" = templatefile("${path.root}/http/ks.pkrtpl.hcl", {
        hostname = var.hostname
        username = var.username
        password_hash = var.password_hash
        kernel_packages = var.kernel_packages
        kernel_exclusions = var.kernel_exclusions
        distro_specific_post = var.distro_specific_post
        package_list = var.package_list
    })
  }
}

build {
  sources = ["source.hyperv-iso.install"]

  provisioner "shell" {
     environment_vars  = ["http_proxy=${var.http_proxy}", "https_proxy=${var.https_proxy}", "no_proxy=${var.no_proxy}"]
     execute_command   = "echo '${var.password}' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
     expect_disconnect = true
     scripts           = [
       "${path.root}/scripts/update.sh",
       "${path.root}/scripts/networking.sh",
       "${path.root}/scripts/hyperv.sh",
       "${path.root}/scripts/azure.sh",
       "${path.root}/scripts/cloud-init.sh"
       ]
  }

  # Run eryph.sh with Python (respects shebang)
  provisioner "shell" {
     environment_vars  = ["http_proxy=${var.http_proxy}", "https_proxy=${var.https_proxy}", "no_proxy=${var.no_proxy}"]
     execute_command   = "echo '${var.password}' | {{ .Vars }} sudo -S -E bash -c '{{ .Path }}'"
     script            = "${path.root}/../linux/scripts/eryph.sh"
  }

  provisioner "shell" {
      environment_vars  = ["http_proxy=${var.http_proxy}", "https_proxy=${var.https_proxy}", "no_proxy=${var.no_proxy}"]
      execute_command   = "echo '${var.password}' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
      expect_disconnect = true
      scripts           = [
        "${path.root}/scripts/cleanup.sh",
        "${path.root}/../linux/scripts/minimize.sh"]
  }
}