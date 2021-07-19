variable "build_directory" {
  type    = string
  default = "../../builds"
}

variable "windows_image_name" {
  type    = string
}

variable "template" {
  type    = string
}

variable "target_path" {
  type    = string
}

variable "unattended_file" {
  type    = string
  default = "Autounattend.pkrtpl.hcl"
}

variable "iso_checksum" {
  type    = string
}

variable "iso_url" {
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

source "file" "unattended_file" {
  content = templatefile("${var.unattended_file}", {
        windows_image_name = "${var.windows_image_name}"
        username           = "${var.username}"
        password           = "${var.password}"
    } )
  target  = "${var.target_path}/Autounattend.xml"
}

build {
  sources = ["source.file.unattended_file"]

}
