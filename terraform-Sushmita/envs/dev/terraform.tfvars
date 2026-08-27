###############################################################################
# DEV environment values.
# Everything here is safe to commit - no secrets.
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

# Replace with your public IP (curl ifconfig.me) before the demo.
admin_cidrs = ["0.0.0.0/0"]

# --- Application identity ---------------------------------------------------
# This one value drives three things and they must all agree:
#   1. ARG USER_NAME in frontend/Dockerfile and admin/Dockerfile
#   2. the ingress paths  /avinash  and  /avinash-admin
#   3. the ECR namespace  avinash-shopnow/*
app_user_name = "avinash"

# --- ECR --------------------------------------------------------------------
# Produces avinash-shopnow/{frontend,admin,backend}, matching the images
# already referenced in kubernetes-Avinash/*.yaml.
# Set to false if the repositories already exist and you have not imported them.
create_ecr_repositories = true
services                = ["frontend", "admin", "backend"]

# --- EKS --------------------------------------------------------------------
cluster_name       = "shopnow-eks-dev"
kubernetes_version = "1.33"

# metrics-server is required by the HPA in Sprint 4.
enable_metrics_server = true

capacity_type  = "ON_DEMAND"
instance_types = ["t3.small"]
desired_size   = 2
min_size       = 2
max_size       = 4

# Add the other three team members so they can run kubectl:
# team_principal_arns = [
#   "arn:aws:iam::968313778667:user/avinash",
#   "arn:aws:iam::968313778667:user/ravi",
#   "arn:aws:iam::968313778667:user/kaushik",
# ]
team_principal_arns = []

# --- State / Jenkins --------------------------------------------------------
# 968313778667 was read off the existing ECR image URLs. Confirm it matches
# `aws sts get-caller-identity` and replace it if not - bootstrap prints the
# correct bucket name for whichever account you are actually in.
tf_state_bucket = "shopnow-tfstate-095355901688"
tf_lock_table_name = "shopnow-tf-locks"

# Flip to true in Sprint 2 when the Jenkins job starts running terraform apply.
allow_jenkins_to_run_terraform = false
