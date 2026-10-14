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

