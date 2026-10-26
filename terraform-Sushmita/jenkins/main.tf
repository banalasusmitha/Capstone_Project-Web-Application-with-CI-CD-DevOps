###############################################################################
# JENKINS SERVER - its own stack, separate from envs/dev
#
# Why separate? Jenkins is what runs `terraform apply` / `destroy` on the
# cluster. If the Jenkins server were part of envs/dev, a destroy started from
# Jenkins would delete the machine running it, half way through. So it lives
# here - like bootstrap/ - and is applied and destroyed on its own.
#
# Why Terraform at all? A server clicked together in the console is invisible
# to `terraform destroy` and keeps billing. That's what happened in August.
#
# Terraform creates the machine. Installing and configuring Jenkins on it is
# Kaushik's (Sprint 1) - or Ravi's Ansible playbook (Sprint 3).
#
# It uses the account's DEFAULT VPC, not the cluster VPC, so destroying the
# cluster never touches Jenkins and vice versa. It reaches the EKS API over
# the cluster's public endpoint.
###############################################################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Latest Amazon Linux 2023, looked up rather than hard-coded.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###############################################################################
# FIREWALL
###############################################################################

resource "aws_security_group" "jenkins" {
  name        = "${var.name}-server-sg"
  description = "Jenkins server: SSH and web UI from trusted IPs only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs
  }

  ingress {
    description = "Jenkins web UI (+ GitHub webhooks if webhook_cidrs is set)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = concat(var.admin_cidrs, var.webhook_cidrs)
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-server-sg" }
}

###############################################################################
# PERMISSIONS
#
# Jenkins runs Terraform for envs/dev, which creates VPCs, an EKS cluster,
# IAM roles and an OIDC provider. That needs admin-level rights: PowerUser
# can't create IAM roles, and IAMFullAccess lets you grant yourself anything
# anyway, so a "narrower" mix would only look narrower. Say so in the viva.
#
# What keeps it safe: no access key exists anywhere. The server gets
# short-lived credentials from the instance profile, and the SSH and UI ports
# are locked to admin_cidrs.
###############################################################################

data "aws_iam_policy_document" "assume" {
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
  # envs/dev looks this role up by exactly this name to give it kubectl access.
  name               = "${var.name}-server-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.name}-server-profile"
  role = aws_iam_role.jenkins.name
}

###############################################################################
# THE SERVER
###############################################################################

resource "aws_key_pair" "jenkins" {
  key_name   = "${var.name}-server-key"
  public_key = var.public_key
}

resource "aws_instance" "jenkins" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type

  # sort() so the choice is stable between runs.
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.jenkins.key_name
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name

  root_block_device {
    # Jenkins workspaces and Docker images grow; 30 GiB leaves room.
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
    # The disk goes when the server goes. A leftover disk is exactly the
    # orphaned volume that was found billing in October.
    delete_on_termination = true
  }

  # Only makes the host Ansible-ready. Jenkins itself is installed by
  # Kaushik or by Ravi's playbook.
  user_data = <<-SCRIPT
    #!/bin/bash
    set -euxo pipefail
    dnf -y install python3 python3-pip git
  SCRIPT

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name    = "${var.name}-server"
    Role    = "jenkins"
    Ansible = "true"
  }

  lifecycle {
    # A newer AMI must not replace the server and wipe Jenkins.
    ignore_changes = [ami]
  }
}

# Fixed IP, so the Jenkins URL and any GitHub webhook survive a stop/start.
# Released automatically on destroy - no orphaned IP left billing.
resource "aws_eip" "jenkins" {
  instance = aws_instance.jenkins.id
  domain   = "vpc"
  tags     = { Name = "${var.name}-server-eip" }
}
