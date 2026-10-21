variable "name" {
  description = "Unique function and execution role name."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.name))
    error_message = "Use 1–64 letters, numbers, underscores or hyphens."
  }
}

variable "source_dir" {
  description = "Directory of standard-library Python sources, with handler.handler as the entrypoint."
  type        = string
  validation {
    condition     = fileexists("${var.source_dir}/handler.py") && !fileexists("${var.source_dir}/platform_http.py")
    error_message = "source_dir must contain handler.py; platform_http.py is reserved for the platform runtime."
  }
}

variable "architecture" {
  type        = string
  description = "CPU architecture. arm64 (Graviton) is cheaper on AWS; standard-library Python runs on either."
  default     = "arm64"
  nullable    = false
  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "Architecture must be arm64 or x86_64."
  }
}

variable "memory_mb" {
  type        = number
  description = "Bounded memory override for these small synchronous services."
  default     = 128
  nullable    = false
  validation {
    condition     = var.memory_mb >= 128 && var.memory_mb <= 1024 && floor(var.memory_mb) == var.memory_mb
    error_message = "Memory must be a whole number of MB between 128 and 1024."
  }
}

variable "timeout_seconds" {
  type        = number
  description = "Bounded execution timeout; not an HTTP rate or spending limit."
  default     = 5
  nullable    = false
  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 30 && floor(var.timeout_seconds) == var.timeout_seconds
    error_message = "Timeout must be a whole number of seconds between 1 and 30."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Explicit retention, avoiding indefinite log storage."
  default     = 14
  nullable    = false
  validation {
    condition     = contains([7, 14, 30, 90], var.log_retention_days)
    error_message = "Supported retention periods are 7, 14, 30 and 90 days."
  }
}

variable "public_url" {
  type        = bool
  description = "Explicit opt-in to unauthenticated URL access. Otherwise callers need AWS IAM permissions and SigV4."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Extra function tags, e.g. LocalStack's _custom_id_ for a predictable local URL."
  default     = {}
  nullable    = false
}
