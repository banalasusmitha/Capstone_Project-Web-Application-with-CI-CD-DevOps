# Cost optimisation

Cost optimisation carries 10% of the project grade, so the decisions below are
deliberate and each one is visible in the Terraform code.

## Estimated running cost (ap-south-1)

| Resource | Config | Approx. cost |
|----------|--------|-------------|
| EKS control plane | 1 cluster | ~$0.10/hour (~$73/month) |
| Worker nodes | 2x t3.medium **Spot** | ~$0.013/hour each (~$0.026/hour) |
| NAT Gateway | **1 shared**, not one per AZ | ~$0.045/hour + data processing |
| EBS volumes | 2x 20 GiB gp3 | ~$1.60/month |
| ECR storage | lifecycle-capped | pennies |
| S3 state + DynamoDB | tiny, on-demand billing | pennies |
| **Total while running** | | **~$0.30-0.35/hour** |

Two hours of demo work costs less than a coffee. Leaving it running for a
month costs well over $100 - which is why the destroy step matters.

## Decisions made in code

**1. Spot worker nodes** - `capacity_type = "SPOT"` in `envs/dev/terraform.tfvars`.
Two instance types are listed (`t3.medium`, `t3a.medium`) so EKS can find Spot
capacity in either pool instead of failing.

**2. One NAT Gateway, not one per AZ** - `single_nat_gateway = true`. A NAT
Gateway costs ~$32/month before data charges; the default in most tutorials is
one per AZ, which triples that for no benefit in a dev environment.
Setting `enable_nat_gateway = false` moves nodes into public subnets and
removes the NAT charge entirely - the cheapest option, at the cost of exposing
nodes to the internet.

**3. Right-sized nodes** - `t3.medium` (2 vCPU / 4 GiB) is the smallest
instance that comfortably runs the three services plus MongoDB and the
monitoring stack. `t3.small` runs out of pods and memory once Prometheus starts.

**4. Node group scales down to 2, up to 4** - `min_size = 2` keeps the cluster
usable; the HPA and node group grow only under load.

**5. ECR lifecycle policies** - untagged layers expire after 3 days and only
the last 10 images per repository are retained. Without this, every Jenkins
build adds ~300 MB of layers that are never cleaned up.

**6. Short CloudWatch retention** - control plane logs are limited to `api` and
`authenticator` types with 7-day retention. `audit` logs are the expensive ones
and are deliberately off. Set `enabled_cluster_log_types = []` to disable
logging altogether.

**7. Small root volumes** - 20 GiB per node instead of the 50 GiB default.

**8. S3 state lifecycle** - non-current state versions expire after 30 days, so
versioning does not grow unbounded.

**9. DynamoDB on-demand billing** - `PAY_PER_REQUEST` means no idle capacity
charge; a few locks per day cost effectively nothing. On Terraform 1.10+ the
table can be dropped entirely in favour of S3 native locking (`use_lockfile`).

**10. No NAT data charges for image pulls** - nodes pull from ECR in the same
region, which stays on the AWS network rather than crossing the NAT Gateway's
per-GB data processing charge. Pulling the MongoDB image from Docker Hub does
cross it, which is one more reason the app images live in ECR.

**11. Reproducible teardown** - the whole environment is one `terraform destroy`
away, so it only runs while the team is actively working.

## Teardown checklist

```bash
cd envs/dev
terraform destroy
```

If destroy hangs on the VPC, something outside Terraform is still attached -
almost always a load balancer created by the NGINX ingress controller:

```bash
kubectl delete svc --all --all-namespaces   # BEFORE terraform destroy
```

Then verify nothing is left running:

```bash
aws eks list-clusters --region ap-south-1
aws ec2 describe-nat-gateways --region ap-south-1 \
  --filter Name=state,Values=available
aws ec2 describe-addresses --region ap-south-1     # unattached EIPs still bill
aws elbv2 describe-load-balancers --region ap-south-1
```

The state bucket and lock table are intentionally **not** destroyed.
