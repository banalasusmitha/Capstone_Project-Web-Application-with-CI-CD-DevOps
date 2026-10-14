# Checks the SSH key guard: a public key passes, a private key or empty string is rejected.
# Mock provider only - never calls AWS. Run from this folder with: terraform init && terraform test

mock_provider "aws" {}

variables {
  name                  = "shopnow-dev"
  subnet_id             = "subnet-mock"
  security_group_id     = "sg-mock"
  instance_profile_name = "mock-profile"
}

run "accepts_public_key" {
  command = plan
  variables { public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMock shopnow-ci-agent" }
}

run "rejects_private_key" {
  command = plan
  variables { public_key = "-----BEGIN OPENSSH PRIVATE KEY-----" }
  expect_failures = [var.public_key]
}

run "rejects_empty_key" {
  command = plan
  variables { public_key = "" }
  expect_failures = [var.public_key]
}
