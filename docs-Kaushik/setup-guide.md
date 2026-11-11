# Jenkins setup guide

How to go from "Terraform just built an empty EC2" to "three working pipelines".
About 20 minutes, most of it waiting for installs.

Everything runs from your WSL terminal. Nothing here creates AWS access keys:
the Jenkins server uses its IAM instance profile.

---

## 0. Before you start

| Need | From |
|---|---|
| The Jenkins EC2 exists | Susmitha: `terraform apply` in `terraform-Sushmita/jenkins/` |
| Your IP in `admin_cidrs` of **both** `jenkins/terraform.tfvars` and `envs/dev/terraform.tfvars` | Send `curl ifconfig.me` to Susmitha |
| The private key `~/.ssh/shopnow-ci-agent` | Susmitha, privately (one key opens the Jenkins server and the CI agent) |

```bash
cd terraform-Sushmita/jenkins
terraform output jenkins_url
terraform output ssh_command
```

---

## 1. SSH in and run the installer

```bash
chmod 600 ~/.ssh/shopnow-ci-agent
ssh -i ~/.ssh/shopnow-ci-agent ec2-user@<jenkins public ip>

# on the server
git clone -b main https://github.com/banalasusmitha/Capstone_Project-Web-Application-with-CI-CD-DevOps.git capstone
cd capstone
sudo bash jenkins-Kaushik/server/install-jenkins.sh --branch main
```

Until the PR is merged, use `kaushik-cicd` instead of `main` in both places.

The script installs Jenkins LTS, Java 21, Docker, Terraform, kubectl, Helm,
Ansible and the plugins in `jenkins-Kaushik/server/plugins.txt`, then loads
`jenkins-Kaushik/server/casc/jenkins.yaml` (Configuration as Code). That file
creates the admin user and the three jobs, so there is **no setup wizard and
no clicking to create jobs**.

At the end it prints the URL and tool versions. Screenshot that output
(`screenshots/jenkins-install.png`).

Get the admin password:

```bash
sudo cat /var/lib/jenkins/casc/admin-password
```

---

## 2. Log in and check

Open `http://<jenkins public ip>:8080`, log in as `admin`.

You should see the folder **ShopNow Capstone** with:

| Job | Jenkinsfile | Sprint |
|---|---|---|
| `1-infra-terraform` | `jenkins-Kaushik/pipelines/Jenkinsfile.infra` | 2 |
| `2-config-ansible` | `jenkins-Kaushik/pipelines/Jenkinsfile.config` | 3 |
| `3-app-cicd` | `Jenkinsfile` (repo root) | 4 |

Check **Manage Jenkins → Plugins → Installed**: Docker Pipeline, Kubernetes CLI,
AWS Credentials, Git, GitHub, Prometheus metrics, Configuration as Code.

---

## 3. Prove the IAM role works (no keys)

Run `1-infra-terraform` with **ACTION = plan**. The *Preflight* stage prints
`Running as: arn:aws:sts::095355901688:assumed-role/shopnow-jenkins-server-role/...`.
That line is the evidence for "Jenkins accesses AWS through an IAM role"
(Sprint 1).

> First run of any job: Jenkins only learns about `parameters {}` and
> `triggers {}` after it has run once. Run each job once with defaults
> (`plan` for infra), then **Build with Parameters** appears.

---

## 4. Credential for the CI agent (Ansible job)

**Manage Jenkins → Credentials → System → Global → Add Credentials**

| Field | Value |
|---|---|
| Kind | SSH Username with private key |
| ID | `ci-agent-ssh` (exactly this) |
| Username | `ec2-user` |
| Private key | Enter directly → paste the contents of `~/.ssh/shopnow-ci-agent` |

This is the only secret Jenkins holds. It never goes in git.

The Jenkins server's IP must also be in `admin_cidrs` in
`envs/dev/terraform.tfvars`, or the CI agent's firewall blocks the SSH.

---

## 5. Trigger builds on code changes

The app job is triggered two ways, both declared in the `Jenkinsfile`:

1. **GitHub webhook (instant).** In **both** repos (`Capstone_Project-...` and
   `shopNow`): Settings → Webhooks → Add webhook
   - Payload URL: `http://<jenkins public ip>:8080/github-webhook/`
   - Content type: `application/json`, event: *Just the push event*

   GitHub must be able to reach port 8080. Susmitha adds GitHub's webhook
   ranges (the `hooks` list from https://api.github.com/meta) to
   `webhook_cidrs` in `jenkins/terraform.tfvars`. Recent Deliveries in the
   webhook page should show a green tick.
2. **SCM polling every 5 minutes** - a fallback that works even if the webhook
   is blocked. Nothing to configure.

---

## 6. Optional: email on failure

**Manage Jenkins → System**
- *E-mail Notification*: SMTP `smtp.gmail.com`, SSL, port 465, user = a Gmail
  address, password = a Gmail **app password**. Click *Test configuration*.
- *Global properties → Environment variables*: `NOTIFY_EMAIL` = team address.

All three pipelines email `NOTIFY_EMAIL` on failure; without it they just
skip the email. Prometheus alerting on failed builds (Ravi) covers the same
requirement without SMTP.

---

## 7. Metrics for Prometheus (Sprint 5)

The Prometheus plugin exposes `http://<jenkins ip>:8080/prometheus/`.
Check it in a browser. Ravi adds a scrape job for it; details in
`pipeline-guide.md` → *Monitoring integration*.

---

## Re-running the installer

Safe at any time: it skips what is already installed. After the PR is merged,
switch the jobs to `main`:

```bash
cd ~/capstone && git checkout main && git pull
sudo bash jenkins-Kaushik/server/install-jenkins.sh --branch main
```
