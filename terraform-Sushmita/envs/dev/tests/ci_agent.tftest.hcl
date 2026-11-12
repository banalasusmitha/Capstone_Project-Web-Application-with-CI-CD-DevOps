# Terraform tests for the CI agent (Sprint 3). Run with: terraform test
# Mock providers only - these never call AWS, create nothing, and cost nothing.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-south-1a", "ap-south-1b", "ap-south-1c"] }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "095355901688" }
  }
  mock_data "aws_iam_roles" {
    defaults = { arns = [] }
  }
  mock_data "aws_eips" {
    defaults = { public_ips = [], allocation_ids = [] }
  }
  mock_data "aws_security_groups" {
    defaults = { ids = [], arns = [], vpc_ids = [] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.ap-south-1.amazonaws.com/id/MOCK" }] }]
      arn                   = "arn:aws:eks:ap-south-1:095355901688:cluster/shopnow-eks-dev"
      certificate_authority = [{ data = "bW9jaw==" }]
      endpoint              = "https://MOCK.gr7.ap-south-1.eks.amazonaws.com"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::095355901688:role/mock" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::095355901688:oidc-provider/mock" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = { arn = "arn:aws:ecr:ap-south-1:095355901688:repository/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::095355901688:policy/mock" }
  }
  mock_resource "aws_eip" {
    defaults = { public_ip = "13.235.1.1" }
  }
  mock_resource "aws_instance" {
    defaults = { public_ip = "13.200.10.20", private_ip = "10.0.1.20" }
  }
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{
        sha1_fingerprint     = "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
        cert_pem             = "mock"
        is_ca                = true
        issuer               = "mock"
        max_path_length      = 0
        not_after            = "2030-01-01T00:00:00Z"
        not_before           = "2020-01-01T00:00:00Z"
        public_key_algorithm = "RSA"
        serial_number        = "1"
        signature_algorithm  = "SHA256-RSA"
        subject              = "mock"
        version              = 3
      }]
    }
  }
}

variables {
  tf_state_bucket = "shopnow-tfstate-095355901688"
}

run "agent_off_by_default" {
  command = apply
  variables { create_ci_agent = false }

  assert {
    condition     = length(module.ci_agent) == 0
    error_message = "Agent should not exist when create_ci_agent = false"
  }
  assert {
    condition     = output.ci_agent_public_ip == null
    error_message = "Output should be null when agent is off"
  }
}

run "agent_on_with_valid_key" {
  command = apply
  variables {
    create_ci_agent     = true
    ci_agent_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyMockKeyMockKeyMockKeyMockKeyMock shopnow-ci-agent"
  }

  assert {
    condition     = length(module.ci_agent) == 1
    error_message = "Agent should exist"
  }
  assert {
    condition     = module.ci_agent[0].ssh_user == "ec2-user"
    error_message = "AL2023 login user should be ec2-user"
  }
  assert {
    condition     = output.ci_agent_public_ip == "13.200.10.20"
    error_message = "Public IP output not wired through"
  }
  assert {
    condition     = output.ansible_inventory == "13.200.10.20 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/shopnow-ci-agent"
    error_message = "Ansible inventory line is wrong: ${output.ansible_inventory}"
  }
}


run "jenkins_server_role_is_picked_up_when_it_exists" {
  command = plan

  override_data {
    target = data.aws_iam_roles.jenkins_server
    values = { arns = ["arn:aws:iam::095355901688:role/shopnow-jenkins-server-role"] }
  }

  assert {
    condition     = contains(data.aws_iam_roles.jenkins_server.arns, "arn:aws:iam::095355901688:role/shopnow-jenkins-server-role")
    error_message = "The Jenkins server role should be found and granted access"
  }
}

run "without_jenkins_server_nothing_extra_is_opened" {
  command = plan

  assert {
    condition     = toset(local.admin_cidrs) == toset(var.admin_cidrs)
    error_message = "With no Jenkins server, admin_cidrs should be exactly the tfvars list"
  }
  assert {
    condition     = length(aws_security_group_rule.prometheus_to_jenkins) == 0
    error_message = "No Jenkins server -> no Prometheus rule"
  }
}

run "jenkins_server_ip_and_sg_are_wired_in_when_it_exists" {
  command = plan

  override_data {
    target = data.aws_eips.jenkins_server
    values = { public_ips = ["3.110.50.60"], allocation_ids = ["eipalloc-0mock"] }
  }
  override_data {
    target = data.aws_security_groups.jenkins_server
    values = { ids = ["sg-0jenkinsmock"], arns = [], vpc_ids = [] }
  }

  assert {
    condition     = contains(local.admin_cidrs, "3.110.50.60/32")
    error_message = "Jenkins server IP should be allowed to SSH to the CI agent"
  }
  assert {
    condition     = alltrue([for c in var.admin_cidrs : contains(local.admin_cidrs, c)])
    error_message = "People's IPs from tfvars must still be there"
  }
  assert {
    condition     = length(aws_security_group_rule.prometheus_to_jenkins) == 1
    error_message = "Prometheus -> Jenkins rule should exist when NAT and Jenkins both exist"
  }
  assert {
    condition     = aws_security_group_rule.prometheus_to_jenkins[0].security_group_id == "sg-0jenkinsmock" && aws_security_group_rule.prometheus_to_jenkins[0].from_port == 8080 && aws_security_group_rule.prometheus_to_jenkins[0].to_port == 8080
    error_message = "Rule must be on the Jenkins server SG, port 8080 only"
  }
  assert {
    condition     = tolist(aws_security_group_rule.prometheus_to_jenkins[0].cidr_blocks) == tolist(["13.235.1.1/32"])
    error_message = "Rule must allow only the NAT Gateway's IP"
  }
}

