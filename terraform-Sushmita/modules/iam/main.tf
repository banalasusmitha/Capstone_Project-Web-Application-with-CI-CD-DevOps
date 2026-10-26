###############################################################################
# IAM MODULE
# Role + instance profile for the Jenkins EC2 server.
# Using an instance profile (instead of long-lived access keys) means no AWS
# secrets are ever stored inside Jenkins.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "jenkins_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  name               = "${var.name}-jenkins-role"
  description        = "Role assumed by the Jenkins EC2 server"
  assume_role_policy = data.aws_iam_policy_document.jenkins_assume.json

  tags = var.tags
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.name}-jenkins-instance-profile"
  role = aws_iam_role.jenkins.name

  tags = var.tags
}

###############################################################################
# Permissions: push/pull images to ECR, talk to the EKS API, read/write the
# Terraform remote state.
###############################################################################

data "aws_iam_policy_document" "jenkins" {
  # GetAuthorizationToken cannot be scoped to a repository.
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = length(var.ecr_repository_arns) > 0 ? var.ecr_repository_arns : ["*"]
  }

  statement {
    sid    = "EKSRead"
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:ListClusters",
      "eks:DescribeNodegroup",
      "eks:ListNodegroups",
      "eks:AccessKubernetesApi"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformStateBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketVersioning"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.tf_state_bucket}"]
  }

  statement {
    sid    = "TerraformStateObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.tf_state_bucket}/*"]
  }

  dynamic "statement" {
    for_each = var.tf_lock_table_name == "" ? [] : [1]

    content {
      sid    = "TerraformStateLock"
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ]
      resources = ["arn:${data.aws_partition.current.partition}:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.tf_lock_table_name}"]
    }
  }
}

resource "aws_iam_policy" "jenkins" {
  name        = "${var.name}-jenkins-policy"
  description = "ECR, EKS and Terraform state permissions for Jenkins"
  policy      = data.aws_iam_policy_document.jenkins.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "jenkins" {
  role       = aws_iam_role.jenkins.name
  policy_arn = aws_iam_policy.jenkins.arn
}

# Optional: let this role run `terraform apply` on envs/dev.
#
# PowerUserAccess alone is NOT enough: it deliberately excludes IAM, and this
# Terraform creates IAM roles, policies and an OIDC provider. So IAMFullAccess
# is attached alongside it. Be honest in the viva: being able to create IAM
# roles is effectively admin, so this role is admin-equivalent while enabled.
#
# Normally OFF - the Jenkins server has its own admin role in ../../jenkins/,
# and this role is only used by the CI agent, which never runs Terraform.
resource "aws_iam_role_policy_attachment" "jenkins_terraform" {
  count = var.allow_jenkins_to_run_terraform ? 1 : 0

  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "jenkins_terraform_iam" {
  count = var.allow_jenkins_to_run_terraform ? 1 : 0

  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/IAMFullAccess"
}

# SSM lets you open a shell on the Jenkins box without exposing port 22.
resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
