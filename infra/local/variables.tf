variable "architecture" {
  type = string
  # make detects the host CPU and sets this, so LocalStack runs the Lambdas without emulation.
  # x86_64 is the fallback for direct terraform runs: it works everywhere, emulated on ARM hosts.
  description = "Lambda architecture matching this machine: arm64 or x86_64."
  default     = "x86_64"
}
