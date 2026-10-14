# Sprint 3 — infrastructure side: the CI agent

Sprint 3 is Ansible plus Jenkins. The playbooks are Ravi's and the Jenkins
jobs are Kaushik's. This guide covers the one piece that belongs to the
infrastructure workstream: **giving Ansible a machine that Terraform built.**

---

## Why this is needed

The Sprint 3 brief says:

> Test the Ansible playbooks on infrastructure **provisioned by Terraform**.

Until now, Terraform created no EC2 instance of its own. The two worker nodes
come from the EKS node group, and they are the **wrong** target for Ansible —
the EKS-optimised image already sets up Docker, the kubelet and pod networking,
and a playbook that touches those fights with EKS.

The Jenkins server Kaushik uses was created by hand in the console, so it is
not "provisioned by Terraform" either.

So this sprint adds a **CI agent**: a plain EC2 instance that

- **Terraform** creates (machine, network, permissions) — this guide
- **Ansible** configures (Docker, kubectl) — Ravi
- **Jenkins** sends builds and deploys to — Kaushik

```
Kaushik's Jenkins
   │
   ├─ Terraform job ──► creates the CI agent EC2           (yours)
   │
   └─ Ansible job ────► installs Docker and kubectl        (Ravi's playbook)
                          on the CI agent
```

The split is the point. **Terraform builds machines. Ansible configures them.**
Terraform here installs nothing on the agent except Python, which Ansible needs
in order to run at all.

---

## What gets created

| Resource | What it is |
|---|---|
| `aws_key_pair` | Registers your SSH **public** key with AWS |
| `aws_instance` | The CI agent — Amazon Linux 2023, `c7i-flex.large` (2 vCPU, 4 GiB), 30 GiB disk |

It reuses things you already built:

- **Subnet** — your first public subnet, so Ansible can reach it over SSH
- **Security group** — the Jenkins one. The EKS control plane already trusts it
  on port 443, which is what `kubectl` deploys from the agent will need
- **IAM instance profile** — the Jenkins one. So the agent can push to ECR and
  deploy to EKS **without any AWS access key stored on it**

Two safety settings worth knowing for the viva:

- **IMDSv2 required** — stops a known class of attack where a web request
  tricks the server into handing out its IAM credentials
- **`ignore_changes = [ami]`** — Amazon publishes new images regularly. Without
  this, a later unrelated `apply` would replace the agent and wipe everything
  Ansible installed

It is **off by default** (`create_ci_agent = false`), so nothing changes in AWS
until you switch it on.

---

## Before you start — two messages

1. **Ask Ravi and Kaushik for their public IPs.** Ansible connects over SSH
   (port 22), and the security group only lets in addresses listed in
   `admin_cidrs`. Ravi needs his laptop's IP; Kaushik needs his **Jenkins
   server's** public IP. They get it with `curl ifconfig.me`.

2. **Ask Avinash whether his images are still in ECR.** See
   [the ECR warning](#warning-ecr-images-and-terraform-destroy) at the end.

---

## Step 1 — Get the latest code

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps
git pull
```

Then unzip the new files over your folder, as you did in Sprint 2:

```bash
ls /mnt/c/Users/*/Downloads/terraform-Sushmita-sprint3*.zip
```

That shows the exact path. Use it in the unzip:

```bash
unzip -o /mnt/c/Users/<your-windows-user>/Downloads/terraform-Sushmita-sprint3.zip -d .
ls terraform-Sushmita/modules
```

You should now see **five** modules: `ci-agent  ecr  eks  iam  vpc`.

---

## Step 2 — Make an SSH key for the agent

An SSH key comes in two halves:

- **Private key** — stays on your computer. Never share it publicly, never commit it.
- **Public key** — the `.pub` file. Safe to share. This is what goes into Terraform.

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/shopnow-ci-agent -C "shopnow-ci-agent" -N ""
```

`-N ""` means no passphrase. That keeps it simple for Jenkins to use later.

Check both halves exist:

```bash
ls -l ~/.ssh/shopnow-ci-agent*
```

You want two files: `shopnow-ci-agent` (private) and `shopnow-ci-agent.pub` (public).

---

## Step 3 — Put the public key into tfvars

This command copies the key in for you, so there's no risk of a paste mistake:

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps/terraform-Sushmita/envs/dev

KEY=$(cat ~/.ssh/shopnow-ci-agent.pub)
sed -i "s|^ci_agent_public_key *= *\"\"|ci_agent_public_key    = \"$KEY\"|" terraform.tfvars
sed -i 's|^create_ci_agent *= *false|create_ci_agent        = true|' terraform.tfvars

grep -E "create_ci_agent|ci_agent_public_key" terraform.tfvars
```

The output must show `create_ci_agent = true` and a line starting
`ci_agent_public_key = "ssh-ed25519 AAAA...`.

**If it starts with `-----BEGIN` you used the private key.** Terraform will
refuse it with a clear error — that check is built in.

---

## Step 4 — Allow your teammates in

Open the file:

```bash
nano terraform.tfvars
```

Find `admin_cidrs` and add the IPs from "Before you start". Your own IP may
have changed since August, so re-check it with `curl ifconfig.me` first:

```hcl
admin_cidrs = [
  "203.212.218.140/32",   # Susmitha
  "x.x.x.x/32",           # Ravi's laptop
  "y.y.y.y/32",           # Kaushik's Jenkins server
]
```

`/32` means "exactly this one address". Save with **Ctrl+O**, **Enter**, **Ctrl+X**.

**Optional, same file:** if you've created IAM users for Ravi and Kaushik, add
their ARNs to `team_principal_arns` so they get `kubectl` access too.

---

## Step 5 — Check everything, without touching AWS

```bash
export AWS_PROFILE=shared
terraform init -backend-config=backend.hcl
terraform validate
terraform test
```

- `init` is **required** — Terraform has to register the new `ci-agent` module.
  Skip it and you get "Module not installed".
- `validate` should print `Success! The configuration is valid.`
- `test` runs the tests in `tests/`. They use **fake (mock) AWS** — they create
  nothing and cost nothing. You want `Success! 2 passed, 0 failed.`

Screenshot the `test` output. Sprint 6 asks for infrastructure test cases, and
this is one.

---

## Step 6 — Commit and push

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps
git add terraform-Sushmita
git status
```

**Check `git status` before committing.** You should see the new module,
the tests, the docs, and four changed files in `envs/dev`. You must **not** see
`shopnow-ci-agent` without `.pub` — the `.gitignore` blocks it, but look anyway.

```bash
git commit -m "Sprint 3: Terraform-provisioned CI agent EC2 for Ansible"
git pull --rebase
git push
```

---

## Step 7 — Apply (only when the team is ready to use it)

This costs money from the moment it finishes, so agree a time with Ravi and
Kaushik first.

```bash
cd terraform-Sushmita/envs/dev
terraform plan -out=tfplan
```

Read the last line before going further:

- **`... to add, 0 to change, 0 to destroy`** — fine. It will be a large number
  if the cluster was destroyed, because everything gets rebuilt.
- **Anything "to destroy"** — stop and check what before applying.

```bash
terraform apply tfplan
```

About 30–40 minutes for a full rebuild. If nobody has run `apply` since
August, this also applies `allow_jenkins_to_run_terraform = true` — committed
then, but only a file change until someone applies it. Kaushik has been
waiting on that.

---

## Step 8 — Prove it works

```bash
terraform output -raw ci_agent_public_ip
terraform output -raw ci_agent_ssh_command
```

`-raw` prints it without quotes, so you can copy it straight in. Run the SSH
command it prints. The first time it asks
"Are you sure you want to continue connecting?" — type `yes`.

Once you're on the agent, three checks:

```bash
python3 --version
aws sts get-caller-identity
aws eks describe-cluster --name shopnow-eks-dev --region ap-south-1 --query cluster.status
```

The second one is the important one. The `Arn` should contain
**`assumed-role/shopnow-dev-jenkins-role`** — proof the machine has AWS access
with **no access key on it at all**. The third should print `"ACTIVE"` — the
agent can see the cluster.

(Amazon Linux 2023 comes with Python 3 and the AWS CLI already installed, which
is why these work before Ansible has run.)

Type `exit` to leave. Screenshot all three.

---

## Step 9 — Hand over

**To Ravi:**

> CI agent is up. Get the IP with `terraform output ci_agent_public_ip` — or use
> the aws_ec2 inventory plugin and group on tag `Role=ci_agent`. Login user is
> `ec2-user`. Python 3 and AWS CLI v2 come with Amazon Linux 2023; Docker and
> kubectl are for your playbook. Don't point the playbook at the EKS worker nodes — EKS
> manages Docker and the kubelet there. I'll send the private key separately.

**To Kaushik:**

> The Terraform permission you asked for is applied now. For the Sprint 3
> chain: Terraform job, then Ansible job against the CI agent. Add the
> private key I'll send as a Jenkins credential ("SSH Username with private
> key", username `ec2-user`). The agent has the Jenkins IAM role attached, so
> builds on it need no AWS keys.

**Send the private key privately** — a direct message, never the group chat,
never git:

```bash
cat ~/.ssh/shopnow-ci-agent
```

---

## Step 10 — Screenshots for the documentation

| Screenshot | Shows |
|---|---|
| `terraform test` passing | Infrastructure tests (Sprint 6 credit too) |
| `terraform plan` summary | What will be created |
| `terraform apply` complete + outputs | The agent IP and inventory line |
| EC2 console listing `shopnow-dev-ci-agent` | It exists, with the `Role = ci_agent` tag |
| SSH session with `aws sts get-caller-identity` | Keyless AWS access via the instance profile |

---

## Cost

The agent adds roughly **$2 a day** while running. It is destroyed along with
everything else by `terraform destroy`, so nothing extra is left behind.

To pause just the agent without tearing down the cluster, set
`create_ci_agent = false` and apply. To bring it back, set it to `true` and
apply again — a few minutes, not 40. It comes back as a **fresh machine**, so
Ravi's playbook has to run on it again.

---

## Troubleshooting

**`Module not installed`** — run `terraform init -backend-config=backend.hcl` again.

**`public_key must be the contents of a .pub file`** — you pasted the private
key. Redo Step 3.

**`The specified instance type is not eligible for Free Tier`** — check what's
allowed and change `ci_agent_instance_type`:

```bash
aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[].InstanceType' --output text --region ap-south-1
```

Avoid `t4g.*` — those are ARM, and the agent uses an x86 image.

**SSH just hangs, then times out** — your IP isn't in `admin_cidrs`. Check
`curl ifconfig.me` against the list, fix, and apply again.

**`Permission denied (publickey)`** — wrong key. The command must use
`-i ~/.ssh/shopnow-ci-agent` (no `.pub`), and the user must be `ec2-user`.

**`RepositoryAlreadyExistsException` during apply** — see below.

---

## Warning: ECR images and `terraform destroy`

The three ECR repositories are managed by this Terraform with
`force_delete = true`. That means **`terraform destroy` deletes the repositories
and every image in them.**

If you destroyed after August 26, Avinash's images are gone. Two possibilities:

- **He hasn't re-pushed** — the next `apply` simply recreates the empty repos.
  He (or Jenkins) pushes the images again afterwards.
- **He re-created the repos by hand to re-push** — `apply` fails with
  `RepositoryAlreadyExistsException`. Import them, then apply again:

```bash
terraform import 'module.ecr[0].aws_ecr_repository.this["avinash-shopnow/frontend"]' avinash-shopnow/frontend
terraform import 'module.ecr[0].aws_ecr_repository.this["avinash-shopnow/admin"]' avinash-shopnow/admin
terraform import 'module.ecr[0].aws_ecr_repository.this["avinash-shopnow/backend"]' avinash-shopnow/backend
```

Once Kaushik's pipeline builds and pushes images automatically, this stops
mattering — every run repopulates ECR. Until then, **tell Avinash before you
destroy.**

---

## For the viva

**"What did you do in Sprint 3?"**

> Sprint 3 is Ansible, so my part was giving Ansible a machine that Terraform
> built. I added a CI agent EC2 as its own module — Terraform creates the
> instance, the key pair and attaches the IAM instance profile, but installs
> nothing beyond Python. Ansible installs Docker and kubectl.
> That's the clean split: Terraform builds machines, Ansible configures them.

**"Why not run Ansible against the EKS nodes?"**

> The EKS-optimised AMI already configures Docker, the kubelet and the CNI.
> A playbook touching those fights with EKS. The agent is the host that
> genuinely needs configuring.

**"How does the agent get AWS access?"**

> An IAM instance profile — the same Jenkins role. No access key is stored on
> the machine; AWS hands it short-lived credentials that rotate automatically.
> `aws sts get-caller-identity` on the box shows the assumed role.

**"Why pass the public key as text instead of a file path?"**

> Jenkins also runs this Terraform. A path like `~/.ssh/key.pub` exists on my
> laptop but not on the Jenkins server, so plan would fail there. A public key
> isn't secret, so it's safe in tfvars and in git.
