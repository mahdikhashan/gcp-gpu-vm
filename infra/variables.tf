variable "project_id" {
  type    = string
  default = "acoustic-alpha-308609"
}

variable "region" {
  type    = string
  default = "asia-southeast1"
}

variable "gpu_worker_name" {
  type        = string
  default     = "whisper-l4-worker"
  description = "Name of the instance"
}

variable "gpu_worker_zone" {
  type        = string
  default     = "asia-southeast1-a"
  description = "Gpu worker zone"
}

variable "gpu_worker_type" {
  type        = string
  default     = "g2-standard-4"
  description = "Gpu worker type"
}

