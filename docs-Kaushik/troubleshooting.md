# Troubleshooting - Jenkins and the pipelines

Find the stage that went red, then the matching row. The console log
(`Console Output`) has the full error; the archived artifacts have the plan,
rendered manifests and test logs.

## Jenkins server

| Symptom | Cause | Fix |
|---|---|---|
| Browser can't open `:8080` | Your IP isn't in `admin_cidrs` (home IPs change) | `curl ifconfig.me`, send to Susmitha, she re-applies `jenkins/` |
| `ssh` times out | Same as above | Same |
| Installer: `Jenkins did not come up` | Usually memory or Java | `sudo journalctl -u jenkins -n 100` |
| Login fails / no jobs after install | JCasC didn't load | `sudo journalctl -u jenkins \| grep -i casc`; re-run the installer |
| A plugin failed to install | Update-center hiccup | Manage Jenkins → Plugins → Available, install it, restart |
| Builds stuck "Waiting for next available executor" | infra job waiting on config job | 3 executors are configured; abort stuck builds |
| `permission denied ... docker.sock` | Jenkins started before it joined the `docker` group | `sudo systemctl restart jenkins` |

## 1-infra-terraform

| Symptom | Cause | Fix |
|---|---|---|
| Preflight: `expected 095355901688` | Instance role from a different account | The Jenkins stack was applied in the wrong account - stop and ask Susmitha |
| `Error acquiring the state lock` | Someone else is running Terraform, or a crashed run | Wait. If nobody is running: `terraform force-unlock <ID>` (only after confirming in the group) |
| Plan wants to **destroy** things on `apply` | State drift or someone changed tfvars | Don't approve. Read `tfplan.txt`, ask Susmitha |
| Destroy hangs on VPC / subnet | A load balancer or ENI is left | Pre-destroy cleanup handles this; if it still hangs: `kubectl delete svc -A --field-selector spec.type=LoadBalancer`, then check EC2 → Load Balancers |
| `No parameters` button | First run of the job | Run once with defaults (plan) |

## 2-config-ansible

| Symptom | Cause | Fix |
|---|---|---|
| `ansible-Ravi/site.yml is not in this branch` | Ravi's work not merged | Merge his PR or set `PLAYBOOK` |
| `No CI agent in Terraform outputs` | `create_ci_agent = false` or env destroyed | Apply the infra job first |
| `Waiting for SSH` times out | Jenkins server IP not in `envs/dev` `admin_cidrs` | Add the Jenkins public IP, re-apply |
| `Permission denied (publickey)` | Wrong key in `ci-agent-ssh` | Re-create the credential with the `shopnow-ci-agent` private key, user `ec2-user` |
| Idempotency check fails | A task changes every run (e.g. `shell` without `creates:`) | Ravi: use modules or `changed_when` |

## 3-app-cicd

| Symptom | Cause | Fix |
|---|---|---|
| Backend unit stage: `npm ci` fails | `package-lock.json` out of sync | Run `npm install` locally in `backend/`, commit the lock file |
| Build: `JavaScript heap out of memory` / killed | 4 GiB server | Swap is set up by the installer; check `free -h`; don't run two app builds at once |
| Container test: `index.html built for /avinash` FAIL | `USER_NAME` not passed or changed | Must match ingress paths and `app_user_name` in tfvars |
| Container test: frontend/admin `/health` FAIL, logs say `host not found in upstream` | nginx config proxies to a name the test network doesn't have | Keep the upstream as `backend-service:5000` |
| Push: `denied` / `repository does not exist` | ECR repos missing (env destroyed with them) | Apply infra; repos are `avinash-shopnow/{frontend,admin,backend}` |
| Deploy: `error: You must be logged in` / `Unauthorized` | Cluster built **before** the Jenkins server, so no Access Entry | Re-run infra `apply` (adds Jenkins' access) |
| Dry-run rejects a manifest | YAML error in `kubernetes-Avinash/` | The log names the file and field |
| Rollout timeout → rolled back | Pods not becoming Ready | Log shows `describe` + events. `ImagePullBackOff`: wrong image path/account. `CrashLoopBackOff`: `kubectl logs deploy/backend-deployment`. Readiness failing: wrong probe path (backend is `/api/health`) |
| Backend crash / `/api/products` FAIL | MongoDB missing or `MONGODB_URI` wrong | Needs the MongoDB StatefulSet and `MONGODB_URI=mongodb://mongodb-0.mongodb-service:27017/shopnow` |
| MongoDB pod `Pending` | PVC has no StorageClass | The pipeline applies gp3; check `kubectl get pvc,sc` |
| UNSTABLE: not reachable through ingress | No Ingress yet, or LB still provisioning | `kubectl get ingress`; a new LB takes 2-5 min - re-run |
| Admin loads but shows no data | Admin nginx has no `/api/` proxy | App repo fix (Avinash): add `location /api/ { proxy_pass http://backend-service:5000/api/; }` |
| Job never starts on push | Webhook can't reach Jenkins | GitHub → Settings → Webhooks → Recent Deliveries. Polling still picks it up within 5 min |

## Useful commands

```bash
# on your machine, with kubectl pointed at the cluster
aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev
kubectl get pods,svc,hpa,ingress -o wide
kubectl describe pod <name>
kubectl logs deploy/backend-deployment --tail=50
kubectl get events --sort-by=.lastTimestamp | tail -20
kubectl rollout history deployment/backend-deployment

# on the Jenkins server
sudo journalctl -u jenkins -f
sudo -u jenkins docker images | head
df -h /var/lib/docker /var/lib/jenkins
```
