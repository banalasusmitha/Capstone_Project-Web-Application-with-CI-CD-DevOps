# Demo-day runbook

Everything goes up once, gets shown and screenshotted, and comes down the
same day. Doing it in one sitting keeps the cost to a few dollars instead of
the hundreds a forgotten cluster costs.

**Time:** about 2 hours of building, plus however long the demo takes.
**Cost:** roughly $5 for a full 8-hour day (estimate). Leave it overnight and
it becomes about $7 a day, every day, until someone destroys it.

Run everything from your WSL terminal.

---

## The day before

- [ ] Everyone has pushed their work to GitHub
- [ ] Everyone who needs SSH or the Jenkins UI has sent their IP
      (`curl ifconfig.me`) - add each to `admin_cidrs` in **both**
      `envs/dev/terraform.tfvars` and `jenkins/terraform.tfvars`
- [ ] The AWS budget alert is set (Billing → Budgets)
- [ ] Agree a start time with the team, and who will take screenshots

---

## 1. Check you're in the right account

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps
git pull
export AWS_PROFILE=shared
aws sts get-caller-identity
```

`Account` must be `095355901688`.

---

## 2. Jenkins server (~3 minutes)

```bash
cd terraform-Sushmita/jenkins
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
terraform output jenkins_url
```

**Build this first.** The cluster gives the Jenkins server `kubectl` access
automatically, but only if the server already exists when the cluster is
built.

Installing Jenkins on it is Kaushik's job (or Ravi's Ansible playbook). The
server is ready for that as soon as this finishes.

---

## 3. The cluster (~20 minutes)

```bash
cd ../envs/dev
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

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

## 5. The app (only if the manifests and images are ready)

Needs the full manifest set in `kubernetes-Avinash/` and the three images in
ECR. The steps are in `kubernetes-Avinash/README.md`. Short version:

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
kubectl apply -f kubernetes-Avinash/
kubectl get pods -w
kubectl get ingress shopnow-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
```

Open `http://<that-address>/avinash` and `/avinash-admin`.

---

## 6. Screenshots

Save these into `screenshots/` in the repo:

| File | Command or page |
|---|---|
| `jenkins-apply.png` | Step 2 `apply` result and `jenkins_url` |
| `cluster-apply.png` | Step 3 `Apply complete!` and outputs |
| `nodes.png` | `kubectl get nodes` and `kubectl top nodes` |
| `system-pods.png` | `kubectl get pods -n kube-system` |
| `storageclass.png` | `kubectl get storageclass` showing `gp3 (default)` |
| `ci-agent-ssh.png` | SSH into the agent, `aws sts get-caller-identity` |
| `app-pods.png` | `kubectl get pods,svc,hpa,ingress` (if step 5 ran) |
| `app-browser.png` | The storefront in a browser (if step 5 ran) |
| `destroy.png` | Step 7 `Destroy complete!` |
| `zero-check.png` | Step 8 all empty |

---

## 7. Tear down - same day, in this order

The order matters: things Kubernetes created (the load balancer, MongoDB's
disk) must go before Terraform deletes the network underneath them.

```bash
cd ~/Capstone_Project-Web-Application-with-CI-CD-DevOps

# app (skip if step 5 didn't run)
kubectl delete -f kubernetes-Avinash/
kubectl delete pvc data-mongodb-0
helm uninstall ingress-nginx -n ingress-nginx

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
aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[].LoadBalancerName'
```

Every line must come back empty: `[]` or `"clusters": []`.

If anything is left, check `docs/troubleshooting.md` before deleting it by hand.
