###############################################################################
# REMOTE STATE
# Values are intentionally left empty and supplied by backend.hcl, so the
# same code can be pointed at a different bucket per environment:
#
#   terraform init -backend-config=backend.hcl
###############################################################################

terraform {
  backend "s3" {}
}
