variable "vm_overrides_file" {
  type    = string
  default = "vm-overrides.pkrtpl.hcl"
}

variable "vm_overrides_path" {
  type    = string
}

variable "override_tmp_enabled" {
  type    = bool
  default = true
}

variable "override_memory_startup_bytes" {
  type    = number
  default = 2147483648
}

variable "override_processor_count" {
  type    = number
  default = 2
}

source "file" "vm_overrides_file" {
  content = templatefile("${var.vm_overrides_file}", {
        tmp_enabled = "${var.override_tmp_enabled}"
        memory_startup_bytes = "${var.override_memory_startup_bytes}"
        processor_count = "${var.override_processor_count}"
    } )
  target  = "${var.vm_overrides_path}"
}

build {
  sources = [
    "source.file.vm_overrides_file"
    ]

}