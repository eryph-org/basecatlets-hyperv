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
  default = "65536"
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

variable "memory" {
  type    = string
  default = "1024"
}

variable "mirror" {
  type    = string
  default = "http://releases.ubuntu.com"
}

variable "mirror_directory" {
  type    = string
}

variable "no_proxy" {
  type    = string
  default = "${env("no_proxy")}"
}

variable "template" {
  type    = string
}


variable "username" {
  type    = string
  default = "ubuntu"
}

 # Generated via: printf ubuntu | mkpasswd -m sha-512 -S ubuntu.. -s
variable "password_hash" {
  type    = string
  default = "$6$ubuntu..$j8zaVg6twXS78j47B7CoujiRvJKBGzHvbFYu52nNcztBsKXqPbBABvfXX51gI/jlS6KH6TjvNxCJT6C9iosNE."
}

variable "password" {
  type    = string
  default = "ubuntu"
}

variable "hostname" {
  type    = string
  default = "ubuntu"
}

variable "boot_cmds" {
  type    = list(string)
}

variable "boot_wait" {
  type    = string
  default = "5s"
}


locals {
  http_directory  = "${path.root}/http"
}

source "hyperv-iso" "install" {
  boot_command       = var.boot_cmds
  boot_wait          = "${var.boot_wait}"   
  communicator       = "ssh"
  disk_block_size    = 1
  cpus               = "${var.cpus}"
  disk_size          = "${var.disk_size}"
  headless           = true
  enable_secure_boot = true
  secure_boot_template = "MicrosoftUEFICertificateAuthority"
  generation         = "2"
  iso_checksum       = "${var.iso_checksum}"
  iso_url            = "${var.mirror}/${var.mirror_directory}/${var.iso_name}"
  memory             = "${var.memory}"
  output_directory   = "${var.build_directory}/packer-${var.template}-hyperv"
  shutdown_command   = "echo '${var.password}' | sudo -S shutdown -P now"
  ssh_password       = "${var.password}"
  ssh_port           = 22
  ssh_timeout        = "10000s"
  ssh_username       = "${var.username}"
  switch_name        = "${var.hyperv_switch}"
  vm_name            = "${var.template}"
  http_content = {
    "/meta-data" = ""
    "/user-data" = templatefile("${path.root}/user-data.pkrtpl.hcl", {
        hostname = "${var.hostname}"
        username = "${var.username}"
        password_hash = "${var.password_hash}"
    } )
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
        "${path.root}/scripts/cloud-init.sh",
       ]
  }

  provisioner "shell" {
      only              = var.username == "vagrant" ? ["hyperv-iso.install"] : ["dummy"]
      environment_vars  = ["HOME_DIR=/home/vagrant", "http_proxy=${var.http_proxy}", "https_proxy=${var.https_proxy}", "no_proxy=${var.no_proxy}"]
      execute_command   = "echo '${var.password}' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
      scripts           = ["${path.root}/scripts/vagrant.sh"]
  }

  provisioner "shell" {
      environment_vars  = ["http_proxy=${var.http_proxy}", "https_proxy=${var.https_proxy}", "no_proxy=${var.no_proxy}"]
      execute_command   = "echo '${var.password}' | {{ .Vars }} sudo -S -E sh -eux '{{ .Path }}'"
      expect_disconnect = true
      scripts           = [
        "${path.root}/scripts/cleanup.sh", 
        "${path.root}/../linux/scripts/minimize.sh"]
  }

   provisioner "breakpoint" {

   }

  post-processor "compress" {
    only   = var.username != "vagrant" ? ["hyperv-iso.install"] : ["dummy"]           
    output =  "${var.build_directory}/${var.template}.zip"
  }

  post-processor "vagrant" {
    only   = var.username == "vagrant" ? ["hyperv-iso.install"] : ["dummy"]
    output = "${var.build_directory}/${var.template}.box"
  }

}
