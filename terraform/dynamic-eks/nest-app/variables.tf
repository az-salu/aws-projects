# This variable determines which commands and scripts to use during deployment based on the operating system.
variable "is_windows" {
  description = "Set to true when running on Windows"
  type        = bool
  default     = true
}