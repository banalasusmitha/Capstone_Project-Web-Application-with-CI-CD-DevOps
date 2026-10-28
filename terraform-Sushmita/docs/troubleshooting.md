# Troubleshooting

## `terraform init` - "Backend configuration changed"

You switched from local to S3 state. Run:

```bash
terraform init -backend-config=backend.hcl -migrate-state
```

## `Error: creating ECR Repository: RepositoryAlreadyExistsException`

The repos were created manually. Either import them (commands in the main
README) or set `create_ecr_repositories = false`.

## `UnsupportedAvailabilityZoneException` when creating the cluster

One of the chosen AZs does not support EKS. Pin the AZs by lowering
`az_count`, or check availability:

```bash
aws ec2 describe-availability-zones --region ap-south-1 \
  --query 'AvailabilityZones[].ZoneName'
```

## `InvalidParameterException: unsupported Kubernetes version`

The default `1.33` may be outside the supported window by the time you run it.
List what the region offers and update `kubernetes_version`:

```bash
aws eks describe-addon-versions --region ap-south-1 \
  --query 'addons[0].addonVersions[0].compatibilities[].clusterVersion' \
  --output text | tr '\t' '\n' | sort -u
```

## Node group stuck in `CREATE_FAILED` / nodes never become Ready

Almost always networking. Check in order:

1. Do the private subnets have a route to the NAT Gateway?
   (`enable_nat_gateway = false` requires nodes in **public** subnets.)
2. Are the subnets tagged `kubernetes.io/cluster/<cluster-name> = shared`?
3. Does the node role have `AmazonEKSWorkerNodePolicy`,
   `AmazonEKS_CNI_Policy` and `AmazonEC2ContainerRegistryReadOnly`?

```bash
aws eks describe-nodegroup --cluster-name shopnow-eks-dev \
  --nodegroup-name shopnow-eks-dev-ng --region ap-south-1 \
  --query 'nodegroup.health'
```

## Spot capacity not available

`InsufficientInstanceCapacity` on a Spot node group. Add more instance types
to `instance_types` (`t3.large`, `t3a.large`, `m5.large`) or temporarily set
`capacity_type = "ON_DEMAND"`.

## `kubectl` returns "You must be logged in to the server (Unauthorized)"

The IAM identity has no access entry. Add its ARN to `team_principal_arns`,
re-apply, then refresh kubeconfig:

```bash
aws sts get-caller-identity          # confirm which identity you are
aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev
```

## MongoDB pod stuck in `Pending` with an unbound PVC

No default StorageClass. Apply the `gp3` StorageClass from the main README.

## Pods stuck in `ImagePullBackOff` and the image URL looks correct

Check whether the account ID in the image URL matches the account your cluster
runs in:

```bash
aws sts get-caller-identity
kubectl describe pod <pod> | grep -i image
```

An ECR repository is only readable from its own account by default. If the
images were pushed to a teammate's account, your nodes cannot pull them - the
repository needs an explicit cross-account policy, or the images need pushing to
your own account. Easiest fix for a capstone: agree on one shared account.

## `terraform destroy` hangs deleting the VPC

A load balancer or ENI created by Kubernetes still exists. Delete the
Kubernetes Services first (`kubectl delete svc --all --all-namespaces`), wait a
minute for AWS to release the ENIs, then destroy again.

## State lock stuck after a cancelled apply

```bash
terraform force-unlock <LOCK_ID>
```

Only do this when you are certain no one else is applying.

## `jenkins/`: `no matching EC2 VPC found`

The Jenkins stack uses the account's default VPC, and it has been deleted.
Recreate it (free), then apply again:

```bash
aws ec2 create-default-vpc --region ap-south-1
```

## Jenkins can't run `kubectl` against the cluster

The cluster only grants the Jenkins server access if the server existed when
the cluster was built. Run `terraform apply` in `envs/dev` once more and it
adds the access.

## Ansible / Jenkins can't SSH to the CI agent (timeout)

The agent only accepts SSH from `admin_cidrs` plus the Jenkins server's
Elastic IP, which `envs/dev` looks up by itself. If the Jenkins stack was
destroyed and rebuilt after the cluster, its IP changed - run `terraform
apply` in `envs/dev` again and it picks up the new one. For a person, check
`curl ifconfig.me` against `admin_cidrs` in `envs/dev/terraform.tfvars`.

## Prometheus shows the Jenkins target as `DOWN`

Prometheus reaches Jenkins through the NAT Gateway, and `envs/dev` allows
that one IP in on port 8080. If the Jenkins stack was re-applied after the
cluster was built, that rule was removed - run `terraform apply` in
`envs/dev` again. Also check the Prometheus plugin is installed in Jenkins
(`http://<jenkins>:8080/prometheus/` should return text).

## A load balancer is still there after teardown

ingress-nginx creates a **Classic** load balancer, which `aws elbv2` doesn't
list. Check with `aws elb describe-load-balancers --region ap-south-1`. If
the cluster is already gone, delete it in the console (EC2 → Load Balancers).
