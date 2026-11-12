# My work on ShopNow: Terraform and AWS (Susmitha)

Our capstone takes the ShopNow MERN app from a `git push` to a running shop on
Amazon EKS. There are four workstreams; mine is the **AWS infrastructure, built
entirely with Terraform**. Everything the other three people run on (the
network, the cluster, the image registry, the IAM roles, the Jenkins server and
the CI agent) comes from the code in this folder.

This page is the short version: what I built, how it went sprint by sprint, what
went wrong, and the proof from our live run. For the full detail, see
[`README.md`](README.md) and [`docs/`](docs/).

---

## What I built

| Piece | What it is |
|---|---|
| `bootstrap/` | S3 bucket for Terraform state (versioned, encrypted), so the whole team shares one state with locking |
| `jenkins/` | The Jenkins server: `t3.medium`, Elastic IP, an IAM role instead of access keys. Its own stack, so destroying the cluster never deletes Jenkins |
| `modules/vpc` | VPC `10.0.0.0/16`, 2 public + 2 private subnets in 2 zones, one shared NAT gateway |
| `modules/eks` | EKS **1.36**, 2 `m7i-flex.large` nodes (scales 2–4), 5 add-ons including the EBS CSI driver and metrics-server |
| `modules/ecr` | 3 image repos (`avinash-shopnow/frontend`, `admin`, `backend`) with scan-on-push and a keep-last-10 rule |
| `modules/iam` | Cluster, node, CI-agent and EBS CSI roles; EKS access entries for Jenkins and the team |
| `modules/ci-agent` | The EC2 that Ravi's Ansible configures: Amazon Linux 2023, IMDSv2 only, tagged `Role=ci_agent` |
| `extras/` | gp3 StorageClass so MongoDB's disk can be created |
| Tests | 10 `terraform test` runs with a mock provider: no AWS calls, no cost |

**Security choices:** no access keys in Git or Jenkins (Jenkins uses an IAM
role); SSH and the Jenkins UI open only to each teammate's own IP (`/32`); the
CI agent's private key never goes into Git; only the cluster's NAT IP may reach
Jenkins on 8080 (for Prometheus).

---

## Sprint by sprint

| Sprint | What I did |
|---|---|
| **1** · Jun–Jul | Created the GitHub repo and README, drew the architecture diagram |
| **2** · Jul–Aug | Wrote the vpc, ecr, iam and eks modules (PR #3); set up S3 remote state; imported the existing ECR repos; applied and verified on the shared account (26 Aug); allowed Jenkins to run Terraform. Write-up with 15 screenshots: [`docs/Sprint2_Terraform_Infrastructure_Susmitha.docx`](docs/Sprint2_Terraform_Infrastructure_Susmitha.docx) |
| **3** · Oct | New `ci-agent` module so Ansible has a Terraform-built server to configure; 3 tests, e.g. a pasted private key is rejected |
| **4** · Oct | Moved the hand-made Jenkins server into Terraform (`jenkins/`); gp3 storage and metrics-server for MongoDB and the HPA; tagged subnets for the load balancer; allowed GitHub webhook IPs; found two app bugs and wrote them up in [`docs/app-integration.md`](docs/app-integration.md) |
| **5** · Oct | Firewall rule so Prometheus (from the cluster's NAT IP) can scrape Jenkins; new `nat_public_ips` output, covered by a test |
| **6** · Oct–Nov | EKS 1.33 → 1.36; cost write-up, $50 budget alert, demo-day runbook and zero-cost check; added teammates' IPs and refreshed the docs (PR #6); **trial live run on 12 Nov**; independent cleanup check after Kaushik's pipeline run |

---

## Live run, 12 November 2026

I built everything from my laptop with Terraform, deployed the app, placed an
order, and tore it all down the same evening. Screenshots are in
[`screenshots/susmitha/`](../screenshots/susmitha/).

| What | Result | Proof |
|---|---|---|
| Jenkins server stack | 7 resources added | [01](../screenshots/susmitha/01-jenkins-terraform-apply.png) |
| Cluster stack plan | 50 to add, **0 to destroy** | [02](../screenshots/susmitha/02-cluster-terraform-plan.png) |
| Cluster stack apply | 50 resources added, outputs for the team | [03](../screenshots/susmitha/03-cluster-terraform-apply.png) |
| Nodes and add-ons | 2 nodes Ready on 1.36, all 5 add-ons, gp3 default | [04](../screenshots/susmitha/04-nodes-addons-storageclass.png), [05](../screenshots/susmitha/05-kubectl-top-nodes.png) |
| App on EKS | 7 pods Running, MongoDB disk Bound, HPA and 3 Ingresses | [07](../screenshots/susmitha/07-app-pods-svc-pvc-hpa-ingress.png) |
| Shop in the browser | Storefront loads; a real order shows up in the admin panel | [08](../screenshots/susmitha/08-storefront.png), [09](../screenshots/susmitha/09-admin-order.png) |
| Teardown | Zero-cost check: every line empty | [10](../screenshots/susmitha/10-zero-check-after-trial-run.png), [11](../screenshots/susmitha/11-zero-check-after-pipeline-run.png) |

Later the same day Kaushik ran the full chain through Jenkins on the same
Terraform code (Terraform → Ansible → build and deploy). After he tore it down,
I checked the account myself ([11](../screenshots/susmitha/11-zero-check-after-pipeline-run.png)):
nothing left running.

---

## What went wrong, and what I changed

- **We started in separate AWS accounts.** A cluster in one account can't pull
  images from another, so we moved everything into one shared account.
- **The Free Plan blocked Spot nodes.** I switched to on-demand `m7i-flex.large`.
- **A `for_each` failed** because its keys weren't known until apply. I rewrote
  it with fixed keys.
- **A forgotten test cluster on Kubernetes 1.33** had moved to extended support
  at 6× the hourly price and used up our credits. I moved to 1.36, added a $50
  budget alert, and every session now ends with a teardown and a zero-cost check.
- **The Jenkins server had been made by hand** in the console, invisible to
  `terraform destroy`. I brought it into Terraform.
- **A half-built cluster and Elastic IPs** were created outside the normal flow.
  I traced them with CloudTrail and removed them with a targeted destroy.
- **The app's URL path is baked in when the images are built.** Without
  `--build-arg USER_NAME=avinash` the app serves at the default `/aryan` and
  every asset 404s behind our ingress. I wrote this up in
  [`docs/app-integration.md`](docs/app-integration.md) and exposed the right
  value as the Terraform output `docker_build_args`; the Jenkins pipeline builds
  with it, and `/avinash` and `/avinash-admin` both returned HTTP 200.

---

## Cost

About **$0.55–0.60 an hour** with everything running, so roughly **$5 for a
demo day**. Between sessions only the S3 state bucket and the ECR repos are
left, a few cents a month. Details: [`docs/cost-optimization.md`](docs/cost-optimization.md).

---

## Where to look

| If you want… | Open |
|---|---|
| How to build and destroy it | [`docs/demo-day-runbook.md`](docs/demo-day-runbook.md) |
| What each teammate gets from this layer | [`TEAM-HANDOFF.md`](TEAM-HANDOFF.md) |
| Every non-obvious line explained | [`docs/code-walkthrough.md`](docs/code-walkthrough.md) |
| Errors we hit and their causes | [`docs/troubleshooting.md`](docs/troubleshooting.md) |
