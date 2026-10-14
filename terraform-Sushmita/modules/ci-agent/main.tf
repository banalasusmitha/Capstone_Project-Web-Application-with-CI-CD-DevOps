###############################################################################
# CI AGENT MODULE  (Sprint 3)
#
# A plain EC2 instance that the Jenkins server sends work to: Docker builds,
# ECR pushes and kubectl deploys. Terraform creates the machine; it installs
# nothing on it. Installing Docker and kubectl is Ansible's job,
# and that split is the point of Sprint 3:
#
#   Terraform -> the machine, its network, its permissions
#   Ansible   -> the software on it
#
# Why not point Ansible at the EKS worker nodes instead? The EKS-optimised AMI
# already configures Docker, the kubelet and the CNI. A playbook aimed there
# fights with EKS. This instance is the host that genuinely needs configuring.
###############################################################################

# Latest Amazon Linux 2023, looked up rather than hard-coded so the instance
# never launches on a stale image.
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
# SSH KEY
#
# Only the PUBLIC key goes in here. It is passed as a string rather than read
# from a file path, because Jenkins also runs this Terraform - a path like
# ~/.ssh/key.pub exists on your laptop but not on the Jenkins server, and
# plan would fail there. A public key is not a secret, so it is safe in
# terraform.tfvars and in git. The private key never leaves the machine
# that generated it.
###############################################################################

resource "aws_key_pair" "agent" {
  key_name   = "${var.name}-ci-agent-key"
  public_key = var.public_key

  tags = merge(var.tags, {
    Name = "${var.name}-ci-agent-key"
  })
}

###############################################################################
# THE INSTANCE
###############################################################################

resource "aws_instance" "agent" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type

  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = true

  key_name = aws_key_pair.agent.key_name

  # The same instance profile as the Jenkins role from modules/iam. The agent
  # does the pushing and deploying, so it needs exactly those permissions -
  # ECR push, EKS access, the state bucket - with no access key on disk.
  iam_instance_profile = var.instance_profile_name

  root_block_device {
    # Docker images pile up on a build machine; 30 GiB leaves room.
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # Just enough to make the host Ansible-ready. Ansible needs Python on the
  # target; AL2023 ships it, this only guarantees it. Every real package
  # decision is left to the playbooks.
  user_data = <<-SCRIPT
    #!/bin/bash
    set -euxo pipefail
    dnf -y install python3 python3-pip
  SCRIPT

  # Require IMDSv2. Blocks the SSRF class of attacks that read an instance's
  # IAM credentials from the metadata service. Hop limit 2 so Docker
  # containers on this host can still reach it.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = merge(var.tags, {
    Name = "${var.name}-ci-agent"

    # Ansible's aws_ec2 dynamic inventory plugin can group hosts on these,
    # so a playbook targets the agent by tag rather than by a hand-kept IP.
    Role    = "ci_agent"
    Ansible = "true"
  })

  lifecycle {
    # The AMI lookup returns a newer image whenever Amazon publishes one.
    # Without this, an unrelated apply would replace the agent and wipe
    # everything Ansible installed on it.
    ignore_changes = [ami]
  }
}
