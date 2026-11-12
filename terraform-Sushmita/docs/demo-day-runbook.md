# Demo-day runbook

Everything goes up once, gets shown and screenshotted, and comes down the
same day. Doing it in one sitting keeps the cost to a few dollars instead of
the hundreds a forgotten cluster costs.

**Time:** about 2 hours of building, plus however long the demo takes.
**Cost:** roughly $5 for a full 8-hour day (estimate, see
`cost-optimization.md`). Leave it overnight and it becomes about $14 a day,
every day, until someone destroys it.

Run everything from your WSL terminal.

---

## The day before

- [ ] Everyone's work is merged into `main` (branch + PR, Kaushik reviews)
- [ ] Everyone who needs SSH or the Jenkins UI has sent their IP
      (`curl ifconfig.me`). Add each one to `admin_cidrs` in
      `jenkins/terraform.tfvars` (Jenkins UI + SSH) and, for anyone who SSHes
      into the CI agent, `envs/dev/terraform.tfvars` too. The Jenkins server's
      own IP is added automatically - don't add it by hand.
- [ ] Anyone who runs `kubectl`/`helm` from their own laptop (Ravi, for
      monitoring) has sent their IAM user ARN (`aws sts get-caller-identity`)
      and it's in `team_principal_arns` in `envs/dev/terraform.tfvars`
- [ ] The CI-agent private key (`~/.ssh/shopnow-ci-agent`) has been sent
      **privately** to Kaushik and Ravi - never in the group chat, never in Git
- [ ] The AWS budget alert is set (Billing → Budgets)
- [ ] Agree a start time with the team, and who will take screenshots

Home IPs can change overnight. Ask everyone to re-run `curl ifconfig.me` on
the morning itself; if one changed, update the tfvars and re-run `apply` -
security group changes take seconds and don't rebuild anything.

---

## 1. Check you're in the right account

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps
git checkout main
git pull
export AWS_PROFILE=shared
aws sts get-caller-identity
```

`Account` must be `095355901688`.

---

## 2. Jenkins server (~3 minutes) - always from your laptop

```bash
cd terraform-Sushmita/jenkins
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
terraform output jenkins_url
terraform output ssh_command
```

**Build this first.** When the cluster is built afterwards, it finds the
Jenkins server automatically and gives it:

- `kubectl` admin on the cluster (via its IAM role), and
- SSH access to the CI agent (its IP joins the agent's security group), so the
  Ansible job can reach it.

Send Kaushik the `jenkins_url` and `ssh_command` output. He installs Jenkins
with `jenkins-Kaushik/server/install-jenkins.sh` and adds the private key as
the Jenkins credential `ci-agent-ssh` (user `ec2-user`).

---

## 3. The cluster (~20 minutes)

### Option A (preferred) - Jenkins runs Terraform

Once Jenkins is up, Kaushik runs the infra pipeline with `ACTION = apply`.
It runs the same Terraform in `envs/dev` using the Jenkins server's **IAM
role** - no access keys anywhere. This is the Sprint 2 requirement, so
screenshot the pipeline's first lines:

```
Running as: arn:aws:sts::095355901688:assumed-role/shopnow-jenkins-server-role/i-...
```

Then the approval prompt, then `Apply complete!`.

### Option B (fallback) - from your laptop

If the pipeline isn't ready or fails, run it yourself. The result is exactly
the same, because both use the same state file in S3.

```bash
cd ../envs/dev
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

Never run A and B at the same time. Whichever starts second waits on the
state lock, and that's what the lock is for.

Before applying, check the plan says **`0 to destroy`**. This also builds the
CI agent, because `create_ci_agent = true`.

If you built the cluster before the Jenkins server by mistake, just run
`terraform apply` here again once Jenkins is up. It adds Jenkins' access.

---

## 4. Connect kubectl

```bash
aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev
kubectl get nodes
kubectl top nodes
kubectl apply -f ../../extras/storageclass-gp3.yaml
kubectl get pods -n kube-system
```

Two nodes `Ready`, every system pod `Running`.

---

## 5. The app

Normally Kaushik's app pipeline deploys it: it builds the images from the
shopNow repo, pushes them to ECR, installs ingress-nginx and applies
`kubernetes-Avinash/`.

Manual fallback, only if the pipeline can't:

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
kubectl apply -f kubernetes-Avinash/
kubectl get pods -w
kubectl get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'; echo
```

Open `http://<that-address>/avinash` and `/avinash-admin`.

---

## 6. Screenshots

Save these into `screenshots/` in the repo:

| File | Command or page |
|---|---|
| `jenkins-apply.png` | Step 2 `apply` result and `jenkins_url` |
| `jenkins-iam-role.png` | Step 3A pipeline log: `Running as: ...assumed-role/shopnow-jenkins-server-role/...` |
| `cluster-apply.png` | Step 3 `Apply complete!` and outputs |
| `nodes.png` | `kubectl get nodes` and `kubectl top nodes` |
| `system-pods.png` | `kubectl get pods -n kube-system` |
| `storageclass.png` | `kubectl get storageclass` showing `gp3 (default)` |
| `ci-agent-ssh.png` | SSH into the agent, `aws sts get-caller-identity` |
| `app-pods.png` | `kubectl get pods,svc,hpa,ingress` |
| `app-browser.png` | The storefront in a browser |
| `billing.png` | Billing → Bills, this month by service (cost evidence) |
| `destroy.png` | Step 7 `Destroy complete!` |
| `zero-check.png` | Step 8 all empty |

---

## 7. Tear down - same day, in this order

The order matters: things Kubernetes created (the load balancer, MongoDB's
disk) must go before Terraform deletes the network underneath them.

### Option A - Jenkins pipeline

Kaushik runs the infra pipeline with `ACTION = destroy`. Its "Pre-destroy
cleanup" stage removes the load balancer and disks first, then it destroys
`envs/dev`. Then **you** destroy the Jenkins server from your laptop,
because Jenkins can't delete the machine it runs on:

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps/terraform-Sushmita/jenkins
terraform destroy
```

### Option B - from your laptop

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps

# what Kubernetes created
kubectl delete -f kubernetes-Avinash/ --ignore-not-found
kubectl delete pvc --all
helm uninstall ingress-nginx -n ingress-nginx
# and Ravi's monitoring, if installed:
helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null; kubectl delete pvc --all -n monitoring

# cluster + network + CI agent. Keeps ECR images, IAM and the state bucket.
cd terraform-Sushmita/envs/dev
terraform destroy -target=module.eks -target=module.vpc

# Jenkins server
cd ../../jenkins
terraform destroy
```

Type `yes` at each prompt, after reading the list of what will be destroyed.

---

## 8. Prove nothing is still billing

```bash
aws eks list-clusters --region ap-south-1
aws ec2 describe-nat-gateways --region ap-south-1 --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
aws ec2 describe-instances --region ap-south-1 --filters Name=instance-state-name,Values=running,stopped --query 'Reservations[].Instances[].InstanceId'
aws ec2 describe-addresses --region ap-south-1 --query 'Addresses[].PublicIp'
aws ec2 describe-volumes --region ap-south-1 --query 'Volumes[].VolumeId'
aws elb describe-load-balancers --region ap-south-1 --query 'LoadBalancerDescriptions[].LoadBalancerName'
aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[].LoadBalancerName'
```

Every line must come back empty: `[]` or `"clusters": []`.

ingress-nginx makes a **Classic** load balancer, which only the `aws elb`
line shows. It's the easiest thing to miss.

If anything is left, check `docs/troubleshooting.md` before deleting it by hand.
