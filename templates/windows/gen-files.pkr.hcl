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

variable "vm_overrides_file" {
  type    = string
  default = "vm-overrides.pkrtpl.hcl"
}

variable "vm_overrides_path" {
  type    = string
}

variable "iso_checksum" {
  type    = string
}

variable "iso_url" {
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

variable "componentElement" {
  type    = string
  default = ""
}

variable "override_tpm_enabled" {
  type    = bool
  default = false
}

variable "override_memory_startup_bytes" {
  type    = number
  default = 4294967296
}

variable "override_processor_count" {
  type    = number
  default = 2
}

source "file" "unattended_file" {
  content = templatefile("${var.unattended_file}", {
        windows_image_name = "${var.windows_image_name}"
        username           = "${var.username}"
        password           = "${var.password}",
        componentElement   = "${var.componentElement}"
    } )
  target  = "${var.target_path}/Autounattend.xml"
}

source "file" "vm_overrides_file" {
  content = templatefile("${var.vm_overrides_file}", {
        tpm_enabled = "${var.override_tpm_enabled}"
        memory_startup_bytes = "${var.override_memory_startup_bytes}"
        processor_count = "${var.override_processor_count}"
    } )
  target  = "${var.vm_overrides_path}"
}

build {
  sources = [
    "source.file.unattended_file",
    "source.file.vm_overrides_file"
    ]

}
