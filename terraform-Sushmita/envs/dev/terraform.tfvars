###############################################################################
# DEV environment values.
# Everything here is safe to commit - no secrets.
# Shared team account: 095355901688
###############################################################################

aws_region  = "ap-south-1"
project     = "shopnow"
environment = "dev"
owner       = "susmitha"

# --- Networking -------------------------------------------------------------
vpc_cidr           = "10.0.0.0/16"
az_count           = 2
enable_nat_gateway = true
single_nat_gateway = true

# Home IPs change - re-run `curl ifconfig.me` and update if SSH stops working.
admin_cidrs = ["203.212.218.140/32"]

# --- Application identity ---------------------------------------------------
# This one value drives three things and they must all agree:
#   1. ARG USER_NAME in frontend/Dockerfile and admin/Dockerfile
#   2. the ingress paths  /avinash  and  /avinash-admin
#   3. the ECR namespace  avinash-shopnow/*
app_user_name = "avinash"

# --- ECR --------------------------------------------------------------------
# The three repos already exist in this account (Avinash pushed images).
# They were imported into state, so Terraform now manages them and applies
# the lifecycle policies and scan-on-push.
create_ecr_repositories = true
services                = ["frontend", "admin", "backend"]

# --- EKS --------------------------------------------------------------------
cluster_name       = "shopnow-eks-dev"
kubernetes_version = "1.33"

# metrics-server is required by the HPA in Sprint 4.
enable_metrics_server = true

capacity_type  = "ON_DEMAND"
instance_types = ["m7i-flex.large", "c7i-flex.large"]
desired_size   = 2
min_size       = 2
max_size       = 4

# Teammates who need kubectl access. Add Ravi and Kaushik once their
# IAM users exist - get each ARN from `aws sts get-caller-identity`.
team_principal_arns = [
  "arn:aws:iam::095355901688:user/avinash-devops",
]

# --- State / Jenkins --------------------------------------------------------
tf_state_bucket    = "shopnow-tfstate-095355901688"
tf_lock_table_name = "shopnow-tf-locks"

# Flip to true in Sprint 2 when the Jenkins job starts running terraform apply.
allow_jenkins_to_run_terraform = false
