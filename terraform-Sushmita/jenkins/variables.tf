variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project tag."
  type        = string
  default     = "shopnow"
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "susmitha"
}

variable "name" {
  description = "Name prefix. The IAM role becomes <name>-server-role, which envs/dev looks up."
  type        = string
  default     = "shopnow-jenkins"
}

variable "instance_type" {
  description = "Jenkins plus Docker builds of the React apps need ~4 GiB; t3.medium has 4 GiB."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root disk in GiB."
  type        = number
  default     = 30
}

variable "admin_cidrs" {
  description = "IPs allowed to SSH and open the Jenkins UI. Use <ip>/32 for each person."
  type        = list(string)
}

variable "webhook_cidrs" {
  description = "Extra CIDRs allowed on 8080 only - GitHub's webhook ranges, from https://api.github.com/meta (the \"hooks\" list)."
  type        = list(string)
  default     = []
}

variable "public_key" {
  description = "Contents of an SSH public key (.pub). Not a secret."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ", var.public_key))
    error_message = "public_key must be the contents of a .pub file. Did you paste the private key by mistake?"
  }
}
