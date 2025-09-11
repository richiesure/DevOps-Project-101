variable "project_name"        { type = string  default = "java-login-app" }
variable "aws_region"          { type = string  default = "eu-west-2" } # London
variable "vpc_cidr"            { type = string  default = "10.10.0.0/16" }
variable "public_subnet_cidr"  { type = string  default = "10.10.0.0/24" }
variable "private_subnet_cidr" { type = string  default = "10.10.1.0/24" }

# Single AZ (you asked for "No AZ") – pick one availability zone
variable "az"                  { type = string  default = "eu-west-2a" }

# EC2/App settings
variable "app_instance_type"   { type = string  default = "t3.small" }
variable "app_min_size"        { type = number  default = 2 }
variable "app_max_size"        { type = number  default = 4 }
variable "app_desired_size"    { type = number  default = 2 }
variable "key_pair_name"       { type = string  default = "" } # leave empty if using SSM only

# App container image tag (set this when you have built/pushed image)
variable "app_image_tag"       { type = string  default = "initial" }

# DB settings
variable "db_engine"           { type = string  default = "mysql" }
variable "db_engine_version"   { type = string  default = "8.0" }
variable "db_instance_class"   { type = string  default = "db.t3.small" }
variable "db_name"             { type = string  default = "appdb" }
variable "db_username"         { type = string  default = "appuser" }
# Password will be generated & stored in Secrets Manager

# Allowed IP for ALB (0.0.0.0/0 for open HTTP while testing; lock down later / add TLS)
variable "alb_allowed_cidr"    { type = list(string) default = ["0.0.0.0/0"] }
