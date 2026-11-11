# Demo day: Jenkins run order and screenshots

Follows Susmitha's `terraform-Sushmita/docs/demo-day-runbook.md`. That runbook
brings up the Jenkins server; after that, **Jenkins does the rest**.

## Run order (~1.5 h)

| # | Who | Step | Time |
|---|---|---|---|
| 1 | Susmitha | Apply `terraform-Sushmita/jenkins/` | 3 min |
| 2 | Kaushik | SSH in, `install-jenkins.sh` (setup-guide.md §1-4) | 15 min |
| 3 | Kaushik | `1-infra-terraform` → `plan`, read summary | 2 min |
| 4 | Kaushik | `1-infra-terraform` → `apply`, approve. Chains Ansible → app deploy automatically | 30 min |
| 5 | Ravi | Install monitoring stack, add Jenkins scrape job | 15 min |
| 6 | Kaushik | Push a small visible change to `shopNow` (e.g. a heading) → webhook → `3-app-cicd` → new version live | 10 min |
| 7 | Kaushik | Show a failure: push a commit that breaks the backend → pipeline stops before ECR, alert fires; revert | 10 min |
| 8 | Avinash | Load test → HPA scales up (`kubectl get hpa -w`) | 5 min |
| 9 | All | Screenshots (below) | 15 min |
| 10 | Kaushik | `1-infra-terraform` → `destroy`, type cluster name. Then Susmitha destroys `jenkins/` | 20 min |

Leaving the environment up overnight costs ~$7/day. Step 10 is not optional.

## Screenshots (save to `screenshots/`)

| File | What it shows | Requirement |
|---|---|---|
| `jenkins-install.png` | Installer summary with tool versions | S1: Jenkins on EC2 + plugins |
| `jenkins-plugins.png` | Manage Jenkins → Plugins: Docker, Kubernetes CLI, AWS, Git | S1: plugins |
| `jenkins-jobs.png` | The ShopNow folder with all three jobs | S6: automated jobs |
| `jenkins-iam-role.png` | Preflight log: `assumed-role/shopnow-jenkins-server-role` | S1: IAM role, no keys |
| `infra-plan.png` | Stage view of `1-infra-terraform` + plan summary | S2 |
| `infra-approval.png` | The Apply approval prompt | S2: safe automation |
| `infra-apply.png` | Successful apply + `kubectl get nodes` stage | S2 |
| `s3-state.png` | S3 console: `dev/terraform.tfstate` in the state bucket | S2: S3 state |
| `ansible-run.png` | `2-config-ansible` stage view (started by infra job) | S3: Ansible after Terraform |
| `ansible-idempotent.png` | Second run `changed=0` | S3 |
| `app-pipeline.png` | `3-app-cicd` stage view, all green | S4 |
| `webhook.png` | GitHub webhook Recent Deliveries (green) + build "Started by GitHub push" | S1/S6: Git trigger |
| `container-tests.png` | Container test PASS lines | S6: test cases |
| `ecr-images.png` | ECR repo with build-number tags | S1/S4: ECR |
| `k8s-resources.png` | `kubectl get deploy,svc,hpa,ingress,pvc` | S4: health checks, scaling |
| `smoke-tests.png` | Smoke test PASS lines + APP_URL | S4/S6 |
| `app-frontend.png`, `app-admin.png` | The live app in a browser | S4 |
| `pipeline-failure.png` | A failed build stopped before push + the alert/email | S5: failure notifications |
| `rollback.png` | Rollout failed → rolled back log, or `rollout history` | S4: resilience |
| `grafana-jenkins.png` | Grafana panel of Jenkins build metrics | S5: Jenkins + Prometheus |
| `infra-destroy.png` | Destroy confirmation + complete | Cost optimisation |
