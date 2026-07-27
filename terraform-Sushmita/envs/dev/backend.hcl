# Fill these in from the `terraform output` of ../../bootstrap
bucket = "shopnow-tfstate-968313778667"
key    = "dev/terraform.tfstate"
region = "ap-south-1"

encrypt = true

# Terraform >= 1.10: lock using an S3 object, no DynamoDB needed.
use_lockfile = true

# Terraform < 1.10: comment out use_lockfile above and uncomment this instead.
# dynamodb_table = "shopnow-tf-locks"
