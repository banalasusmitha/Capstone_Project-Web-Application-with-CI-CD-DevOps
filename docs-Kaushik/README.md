# CI/CD documentation (Kaushik)

| Document | Read it when |
|---|---|
| [setup-guide.md](setup-guide.md) | Building the Jenkins server and connecting GitHub, AWS and the CI agent |
| [pipeline-guide.md](pipeline-guide.md) | Understanding or presenting what each job and stage does, and the monitoring integration |
| [troubleshooting.md](troubleshooting.md) | Something went red |
| [demo-checklist.md](demo-checklist.md) | Demo day: run order and the screenshot list |

Code lives in [`../jenkins-Kaushik/`](../jenkins-Kaushik/) and the root
[`Jenkinsfile`](../Jenkinsfile).

## Requirement coverage (my part)

| Brief | Done by |
|---|---|
| S1 Jenkins server on EC2 with Docker, Kubernetes, AWS CLI plugins | `install-jenkins.sh` + `plugins.txt` (server itself: Terraform, `terraform-Sushmita/jenkins`) |
| S1 Jenkins accesses AWS/EKS with IAM roles | Instance profile + EKS Access Entry; no keys in any Jenkinsfile; account check in every Preflight |
| S1 Git integration triggers builds | `githubPush()` + `pollSCM` in `Jenkinsfile`, webhooks on both repos |
| S2 Jenkins job automating Terraform, state in S3 | `1-infra-terraform` (plan / approve / apply / destroy) |
| S3 Jenkins job running Ansible, triggered after Terraform | `2-config-ansible`, started by `1-infra-terraform` |
| S4 Multi-stage pipeline: build, test, push to ECR, deploy to EKS | `3-app-cicd` |
| S4 Health checks and auto-scaling in the deployment pipeline | Rollout waits on readiness probes, automatic rollback, HPA shown after deploy (probes/HPA themselves: Avinash's manifests) |
| S5 Jenkins integrated with Prometheus/Grafana; notifications on failure | Prometheus plugin endpoint + scrape/alert config for Ravi; email on failure |
| S6 Test cases | Unit/static checks, `tests/container-test.sh`, `tests/smoke-test.sh` |
| S6 Automated triggers for each stage | push → build → deploy; apply → Ansible → deploy |
| S6 Documentation | This folder |
| Cost | Destroy job cleans up Kubernetes-made load balancers/volumes first; image prune; swap instead of a bigger instance |
