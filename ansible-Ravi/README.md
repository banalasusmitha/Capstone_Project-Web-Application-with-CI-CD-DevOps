# Ansible - ShopNow CI-agent configuration (Ravi)

This directory contains the Sprint 3 Ansible implementation for the capstone.
It configures only the Terraform-managed Amazon Linux 2023 CI agent. It must
**not** target EKS worker nodes.

## Fixed integration values

- AWS region: `ap-south-1`
- EKS cluster: `shopnow-eks-dev`
- Terraform stack: `terraform-Sushmita/envs/dev/`
- CI-agent tag: `Role=ci_agent`
- SSH user: `ec2-user`
- Playbook: `ansible-Ravi/site.yml`
- Dynamic inventory: `ansible-Ravi/inventory/aws_ec2.yml`

The playbook installs Docker, Git, Java 21 (Amazon Corretto), and `kubectl` 1.36.2.
It enables and starts Docker and adds `ec2-user` to the `docker` group. The
`kubectl` binary is downloaded with a SHA-256 checksum check. AWS CLI v2 and
Python 3 are already installed by the Terraform CI-agent image/handoff.

## Prerequisites

Run Ansible from the Jenkins server or another approved control machine with:

- `ansible-core >= 2.17.0`, Python >= 3.9, and the `amazon.aws` collection version pinned in `requirements.yml`.
- Python dependencies `boto3 >= 1.35.0` and `botocore >= 1.35.0` available to Ansible.
- AWS credentials with `ec2:DescribeInstances` for dynamic inventory. On the Jenkins EC2 server, use the Terraform-managed instance profile; do not add static AWS keys to this repository.
- The CI-agent private key available locally or injected as a Jenkins **SSH Username with private key** credential. Never commit or screenshot the private key.
- The CI agent running and tagged `Role=ci_agent` in the shared AWS account.
- The Jenkins server's public IP allowed in `admin_cidrs` in `terraform-Sushmita/envs/dev/terraform.tfvars`, so it can SSH to the CI agent. Ask Susmitha to apply any required infrastructure change.

For local WSL use, activate the team's documented profile before running these commands: `export AWS_PROFILE=shared`. Confirm the account with `aws sts get-caller-identity`. Do not add a profile name to the inventory file because Jenkins should use its instance role.

## Install controller dependencies

From this directory:

```bash
python3 -m pip install --user 'boto3>=1.35.0' 'botocore>=1.35.0'
ansible-galaxy collection install -r requirements.yml
```

Check which AWS identity is active and confirm it is the team's shared account:

```bash
aws sts get-caller-identity
```

## Validate before connecting

Run these from `ansible-Ravi/`:

```bash
ansible-inventory -i inventory/aws_ec2.yml --graph
ansible-inventory -i inventory/aws_ec2.yml --list
ansible ci_agent -i inventory/aws_ec2.yml --list-hosts
ansible-playbook -i inventory/aws_ec2.yml site.yml --syntax-check
```

The graph should contain the `ci_agent` group and only the CI agent. If no
hosts appear, stop and check the AWS identity, region, EC2 tag, running state,
`boto3`/`botocore`, and `ec2:DescribeInstances` permissions. Do not work around
an empty inventory by targeting worker-node IP addresses.

## Test and apply

The private key path below is the local filename documented by the Terraform
handoff. Use the actual credential-file path provided by Jenkins when executing
inside a job.

```bash
ansible-playbook -i inventory/aws_ec2.yml site.yml \
  --private-key ~/.ssh/shopnow-ci-agent --check --diff

ansible-playbook -i inventory/aws_ec2.yml site.yml \
  --private-key ~/.ssh/shopnow-ci-agent
```

The check-mode result is only a preview; the second command is required to
verify package installation and service startup. Run the real playbook twice.
The second run should report no configuration changes apart from any repository
metadata refresh. If `ec2-user` was added to the Docker group, an existing SSH
or Jenkins-agent process needs a fresh login session before it sees the new
supplementary group.

## Verify on the CI agent

```bash
docker --version
git --version
java -version
kubectl version --client
id ec2-user
systemctl is-enabled docker
systemctl is-active docker
aws sts get-caller-identity
```

`id ec2-user` should include `docker`; Docker should be `enabled` and `active`.
The AWS caller identity should show the intended instance role and shared account.

The playbook intentionally does not install Jenkins, configure EKS worker
nodes, or write AWS access keys. Terraform creates the machine and IAM
association; Ansible configures packages on that machine.

## Screenshot checklist

Save genuine command output in the repository's shared `screenshots/` directory.
Do not include private-key contents, access tokens, or secrets.

1. `ravi-ansible-01-inventory.png` - `ansible-inventory --graph` showing only `ci_agent`.
2. `ravi-ansible-02-syntax-check.png` - successful syntax check.
3. `ravi-ansible-03-first-run.png` - first real playbook run recap.
4. `ravi-ansible-04-idempotency.png` - second run recap showing no repeated changes.
5. `ravi-ansible-05-tools-verified.png` - Docker, Git, Java, kubectl and `id ec2-user` checks.

## Troubleshooting

- **No hosts in inventory:** confirm `aws sts get-caller-identity`, region `ap-south-1`, instance state `running`, tag `Role=ci_agent`, AWS inventory dependencies, and `ec2:DescribeInstances` permissions.
- **SSH timeout:** current public source IP must be added to `admin_cidrs`; the Jenkins server public IP must be allowed too. Coordinate with Susmitha before applying Terraform.
- **Permission denied (publickey):** use the matching private key and `ec2-user`; never use the `.pub` file as the private key.
- **`docker` permission denied after playbook:** start a new login session or reconnect/restart the Jenkins agent process so it inherits the added group.
- **kubectl download/checksum failure:** check outbound network/DNS access from the controller/target and retry. Do not disable checksum verification as a workaround.
- **Kubernetes authorization failure:** first run `aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev` with the intended identity, then verify that identity has EKS access. The playbook installs the CLI; it does not grant Kubernetes permissions.
