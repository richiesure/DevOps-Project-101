variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "java-login-app"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "app_image_tag" {
  description = "Application image tag"
  type        = string
  default     = "latest"
}

variable "app_desired_size" {
  description = "Desired number of instances in the ASG"
  type        = number
  default     = 2
}

variable "app_min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 1
}

variable "app_max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 3
}
