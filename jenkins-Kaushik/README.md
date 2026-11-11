# Jenkins - CI/CD (Kaushik)

```
jenkins-Kaushik/
├── server/
│   ├── install-jenkins.sh     # turns the Terraform-built EC2 into the Jenkins server
│   ├── plugins.txt            # plugins it installs
│   └── casc/jenkins.yaml      # Configuration as Code: admin user, security, the 3 jobs
├── pipelines/
│   ├── Jenkinsfile.infra      # job 1-infra-terraform   (Sprint 2)
│   └── Jenkinsfile.config     # job 2-config-ansible    (Sprint 3)
└── tests/
    ├── container-test.sh      # tests images before they are pushed
    └── smoke-test.sh          # tests the live deployment on EKS
../Jenkinsfile                 # job 3-app-cicd          (Sprint 4) - at repo root for the webhook
```

Flow: `1-infra-terraform` (apply) → `2-config-ansible` → `3-app-cicd`, and
every git push → `3-app-cicd`.

Setup: [`../docs-Kaushik/setup-guide.md`](../docs-Kaushik/setup-guide.md).
How it works: [`../docs-Kaushik/pipeline-guide.md`](../docs-Kaushik/pipeline-guide.md).

### What the pipelines expect from the rest of the repo

| From | Expected |
|---|---|
| `terraform-Sushmita/envs/dev` | `backend.hcl`; outputs `ci_agent_public_ip`; `extras/storageclass-gp3.yaml` |
| `ansible-Ravi/` | `site.yml`; optional `inventory/aws_ec2.yml` |
| `kubernetes-Avinash/` | Deployments named `frontend-deployment`, `admin-deployment`, `backend-deployment`; Services `frontend-service`, `admin-service`, `backend-service`; images under `.../avinash-shopnow/<svc>` (any tag - the pipeline sets it) |
| `shopNow` app repo | `frontend/`, `admin/`, `backend/` each with a Dockerfile |
