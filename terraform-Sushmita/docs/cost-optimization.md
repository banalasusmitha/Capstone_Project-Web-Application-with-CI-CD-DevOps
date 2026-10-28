# Cost optimisation

Cost optimisation carries 10% of the project grade, so the decisions below are
deliberate and each one is visible in the Terraform code.

## Estimated running cost (ap-south-1)

Everything that exists on demo day, on-demand prices, Mumbai region
(checked 28 Oct 2026; the AWS bill is the final word).

| Resource | Config | Approx. cost |
|----------|--------|-------------|
| EKS control plane | 1 cluster, Kubernetes 1.36 (standard support) | $0.10/hour |
| Worker nodes | 2x `m7i-flex.large` on-demand | ~$0.10/hour each (~$0.20/hour) |
| CI agent | 1x `c7i-flex.large` | ~$0.085/hour |
| Jenkins server | 1x `t3.medium` | ~$0.045/hour |
| NAT Gateway | **1 shared**, not one per AZ | ~$0.05/hour + data processing |
| Load balancer | 1, created by ingress-nginx | ~$0.03/hour |
| Public IPv4 addresses | ~5 (Jenkins, NAT, CI agent, load balancer) | $0.005/hour each (~$0.025/hour) |
| EBS volumes | ~110 GiB gp3: nodes, Jenkins, agent, MongoDB | ~$0.015/hour |
| ECR storage | lifecycle-capped | pennies |
| S3 state + lock | tiny, on-demand billing | pennies |
| **Total while running** | | **~$0.55-0.60/hour** |

An 8-hour demo day costs about $5. Left running, the same setup costs about
$14 a day, or roughly $400 a month - which is why the destroy step matters.

## Decisions made in code

**1. On-demand nodes now, Spot is one line away** - `capacity_type` in
`envs/dev/terraform.tfvars`. The design started on Spot `t3.medium`, but the
AWS Free Plan rejected it, so the nodes moved to on-demand `m7i-flex.large`.
The account is now on the paid plan, so `capacity_type = "SPOT"` would roughly
halve the node cost (~$0.05/hour instead of ~$0.10/hour each). It stays on
on-demand for the demo, so a Spot interruption can't take the app down
mid-presentation. Two instance types are listed so EKS has a fallback pool.

**2. One NAT Gateway, not one per AZ** - `single_nat_gateway = true`. A NAT
Gateway costs ~$32/month before data charges; the default in most tutorials is
one per AZ, which triples that for no benefit in a dev environment.
Setting `enable_nat_gateway = false` moves nodes into public subnets and
removes the NAT charge entirely - the cheapest option, at the cost of exposing
nodes to the internet.

**3. Right-sized nodes** - `m7i-flex.large` (2 vCPU / 8 GiB) runs the three
services, MongoDB and the monitoring stack on two nodes. `t3.small` runs out of
pods and memory once Prometheus starts. The flex types are cheaper than the
matching standard `m7i`/`c7i` sizes, and were on the Free Plan's short list of
allowed instance types.

**4. Node group scales down to 2, up to 4** - `min_size = 2` keeps the cluster
usable; the HPA and node group grow only under load.

**5. ECR lifecycle policies** - untagged layers expire after 3 days and only
the last 10 images per repository are retained. Without this, every Jenkins
build adds ~300 MB of layers that are never cleaned up.

**6. Short CloudWatch retention** - control plane logs are limited to `api` and
`authenticator` types with 7-day retention. `audit` logs are the expensive ones
and are deliberately off. Set `enabled_cluster_log_types = []` to disable
logging altogether.

**7. Small root volumes** - 20 GiB gp3 per node (the EKS default for Linux),
deliberately not raised "just in case"; 30 GiB for Jenkins and the CI agent,
which keep Docker images.

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

**12. Build machines only exist on demo day** - the Jenkins server
(`jenkins/`) and the CI agent (`create_ci_agent`) are Terraform-managed like
everything else, with disks that are deleted with the instance. Nothing in the
CI/CD setup is a hand-made server that can be forgotten.

## Teardown checklist

The full order is in `docs/demo-day-runbook.md` (steps 7 and 8). In short:

1. Delete what Kubernetes created - the app, MongoDB's disk (PVC) and the
   ingress-nginx load balancer. Terraform doesn't know about these, and the
   load balancer blocks the VPC from being deleted.
2. `terraform destroy` in `envs/dev` (cluster, network, CI agent).
3. `terraform destroy` in `jenkins/`.
4. The zero-check:

```bash
aws eks list-clusters --region ap-south-1
aws ec2 describe-nat-gateways --region ap-south-1 --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
aws ec2 describe-instances --region ap-south-1 --filters Name=instance-state-name,Values=running,stopped --query 'Reservations[].Instances[].InstanceId'
aws ec2 describe-addresses --region ap-south-1 --query 'Addresses[].PublicIp'
aws ec2 describe-volumes --region ap-south-1 --query 'Volumes[].VolumeId'
aws elb describe-load-balancers --region ap-south-1 --query 'LoadBalancerDescriptions[].LoadBalancerName'
aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[].LoadBalancerName'
```

ingress-nginx creates a **Classic** load balancer by default, which only shows
up in `aws elb`, not `aws elbv2` - so both are checked.

The state bucket and lock table are intentionally **not** destroyed.

---

## October 2026: the credits incident, and what changed

### What happened

The account ran out of its $115.94 in Free Plan credits and was suspended in
mid-October. Four things caused it:

1. **A cluster was created on 27 August and never destroyed.** It ran for
   about two months.
2. **Its Kubernetes version (1.33) moved into EKS extended support** while it
   was running. Extended support costs **$0.60 per cluster-hour instead of
   $0.10**, six times as much.
3. **A 20 GiB disk had been orphaned since 3 August**, left behind by an EC2
   instance that was deleted without it.
4. **A Jenkins server and its Elastic IP were created by hand in the
   console.** Terraform didn't know about them, so `terraform destroy` never
   removed them.

None of these were visible without going looking. That's the real lesson:
**cloud costs fail silently.**

### What was done about it

| Fix | Effect |
|---|---|
| Destroyed the cluster: 41 resources, with `-target` so ECR images, IAM and the state bucket were kept | Stopped the big charges immediately |
| Deleted the orphaned disk | Stopped a small charge that had run since August |
| Moved Terraform to **Kubernetes 1.36**, checked with `aws eks describe-cluster-versions` | Control plane back to $0.10/hour |
| **AWS Budget alert** at $50/month | The next forgotten resource sends an email |
| **Jenkins server moved into Terraform** (`jenkins/`), with `delete_on_termination = true` on its disk and an Elastic IP released on destroy | One `destroy` removes it completely; no orphans possible |
| **Demo-day runbook** (`docs/demo-day-runbook.md`) | Everything goes up and comes down the same day, ending with a check that nothing is left |

### The rules this produced

- **Destroy the same day.** No cluster runs overnight unless someone is
  actively using it.
- **Nothing gets created by hand.** If it isn't in Terraform, `destroy` can't
  remove it.
- **Check the Kubernetes version before every build.** Versions move into
  extended support on a schedule, and the price jumps when they do.
- **End every session with the zero-check** from step 8 of the runbook.

### Possible next step

The account is now on the paid plan, so the Free Plan's instance-type limits
no longer apply. Moving the worker nodes back to **Spot** `t3.medium` would
cut node cost by about 60–70%. It was left on on-demand for now, to avoid
Spot interruptions during the demo.
