# Concepts, explained from questions I actually asked

Notes from working through this project. Written as answers to real confusions,
not as a textbook. If something below reads as obvious now, it wasn't at the
time — leave it in.

---

## 1. Who writes Terraform files in industry?

Engineers. `.tf` and `.tfvars` files are written and owned by DevOps or platform
engineers, and reviewed in pull requests like any other code.

AI assists heavily now — drafting a first version, explaining errors, suggesting
a layout. But the engineer owns the result, because they are the one who gets
paged when it breaks and who defends it in review. Code being AI-drafted is
normal; not understanding it is not.

---

## 2. `resource`, `variable`, `output` — mapped to the AWS console

The console flow I already knew, translated:

| In the console I… | In Terraform |
|---|---|
| Click "Launch instance" | `resource "aws_instance"` |
| Choose t2.micro | `variable "instance_type"` |
| Pick a subnet | `variable "subnet_id"` |
| Open port 22 from 0.0.0.0/0 | `resource "aws_security_group"` + a variable for the CIDR |
| Read the Public IP off the screen afterwards | `output "public_ip"` |

**resource** — creates something in AWS. The only one of the three that does.

**variable** — an input. A form field left blank so someone can fill it in later.

```hcl
variable "ssh_allowed_cidrs" {
  default = ["0.0.0.0/0"]
}

ingress {
  cidr_blocks = var.ssh_allowed_cidrs   # dev allows everyone, prod allows the office IP
}
```

**output** — a value handed back out.

**Why I never noticed outputs in the console:** the console just *shows* you the
instance ID and public IP automatically after creating something. Terraform is a
command line, so you have to declare which values you want printed. Same
information, explicitly requested.

Outputs matter more in Terraform because they replace copy-paste between
services:

```hcl
output "public_subnet_ids" { value = aws_subnet.public[*].id }   # VPC module publishes
module "eks" { public_subnet_ids = module.vpc.public_subnet_ids } # EKS module receives
```

Without the output block, that value stays trapped inside the module even though
the subnets exist.

---

## 3. Why there aren't 6–7 variables per resource

My assumption was that each resource needs its own set of variables and outputs,
so 20 resources means 130 variables. Wrong. The real numbers in my VPC module:

| | Count |
|---|---|
| Resources | ~20 |
| Variables | 7 |
| Outputs | 7 |

Every setting on a resource gets its value from one of four places, and only the
last one becomes a variable:

1. **Hard-coded** — `enable_dns_support = true`. A fixed decision.
2. **From another resource** — `vpc_id = aws_vpc.this.id`. Doesn't exist until
   Terraform creates it, so it can't be an input.
3. **Looked up** — `data.aws_availability_zones.available`. Terraform asks AWS.
4. **From a variable** — only when there's a real choice to expose.

Some resources have zero variables. The internet gateway is one — there's
nothing to configure about it. It either exists or it doesn't.

**The test for making something a variable:** would anyone ever want this
different?

- Region → yes, `ap-south-1` vs `us-east-1` → variable
- Node count → yes, 2 in dev, 6 in prod → variable
- `enable_dns_support = true` → no, EKS breaks without it → hard-code

**Fewer variables is often better.** Every variable is a way for someone to
misconfigure the system. Exposing `enable_dns_support` would create a switch
whose only purpose is breaking EKS. Deliberately *not* making something
configurable is a design decision.

Same logic for outputs: publish a value only if someone downstream needs it.
The VPC creates 20 resources and outputs 7 — nobody needs route table
association IDs.

---

## 4. A resource is not just a server

This was the main confusion. "Resource" sounded like it meant EC2, because
that's what you launch.

**A resource is anything AWS can create that gets its own ID.** A server is one.
So is a network, a firewall, a permission, a bucket, a route.

| Thing | ID |
|---|---|
| VPC | `vpc-0a1b2c3d` |
| Subnet | `subnet-4e5f6g7h` |
| Security group | `sg-8i9j0k1l` |
| EC2 instance | `i-2m3n4o5p` |

Four separate things, four IDs, four `resource` blocks.

### Why I thought VPC lived "under" EC2

Because the launch wizard shows a Network dropdown with a VPC already in it. But
that VPC **already existed** — AWS creates a default VPC in every account, and
the dropdown just picks which existing network to plug into.

Go to **VPC** in the services menu: it's a separate service with its own
dashboard. Delete every EC2 instance and the VPC is still there.

The console hands you a default so beginners aren't blocked on day one.
Terraform assumes nothing, so the order reverses:

```
console:    launch EC2  →  pick a VPC from the dropdown
terraform:  build VPC   →  then put things inside it
```

---

## 5. Resources versus settings

Ports and IP ranges are **settings**, not resources.

```hcl
resource "aws_security_group" "jenkins" {   # ONE resource → sg-abc123
  ingress { from_port = 22   ; cidr_blocks = ["0.0.0.0/0"] }   # settings
  ingress { from_port = 8080 ; cidr_blocks = ["0.0.0.0/0"] }   # settings
}
```

Two ports, two IP ranges, still one resource with one ID. In the console this is
one security group with two rows in its rules table.

**The test:** does it get its own AWS ID and its own row in the console?
Resource. Is it a field you fill in on that thing? Setting.

**Fastest way to check:** open the AWS console → VPC. The left sidebar reads
*Your VPCs, Subnets, Route tables, Internet gateways, NAT gateways, Security
groups, Elastic IPs*. **Each menu item is a resource type. Each row inside is
one resource.** Click into a row — everything in the detail panel is a setting.
Terraform isn't inventing categories; it mirrors how AWS is organised.

---

## 6. Subnet, route table, security group — what each actually does

The analogy that made it click:

- **VPC** = a floor of a building. Your own space.
- **Subnet** = a room on that floor. Things sit in rooms, not floors.
- **Route table** = the signs in the corridor. "Exit this way."
- **Security group** = the guard on the door. Checks who you are and what you want.

### Precisely

**Subnet** — a slice of the VPC's address range, tied to one availability zone.
My VPC is `10.0.0.0/16` (65,536 addresses), split into four `/20` blocks of
~4,000 each. Every instance takes its private IP from the subnet it sits in.

**Route table** — a list of "traffic for X goes to Y", attached to a subnet.
One line is the entire difference between public and private:

```
public subnet:   0.0.0.0/0 → internet gateway   (two-way)
private subnet:  0.0.0.0/0 → NAT gateway        (outbound only)
```

The subnets are otherwise identical. Change the route table and a public subnet
becomes private.

**Security group** — wraps the *instance*, not the subnet. Checks which port,
from which IP.

### Route table vs security group

| | Route table | Security group |
|---|---|---|
| Attached to | the subnet | the instance |
| Answers | *where does this go?* | *is this allowed?* |
| Analogy | road signs | door guard |

Both have to agree. A route table with no internet route means traffic can't
leave even if the security group allows it. A security group blocking 22 stops
SSH even if the route exists.

**Likely exam question — "SSH isn't working, what do you check?"** Answer both:
is there a route to an internet gateway, and does the security group allow port
22 from my IP?

### One oddity

`aws_route` has no visible ID in the console — it appears as a row inside a route
table. Terraform still treats it as a separate resource so a single route can be
added or removed without rewriting the whole table.

Also: attaching a route table to a subnet is *itself* a resource
(`aws_route_table_association`, ID `rtbassoc-...`). That's why my count of 20
includes four associations.

---

## 7. What my 20 VPC resources actually are

| Resource | ID prefix | How many |
|---|---|---|
| VPC | `vpc-` | 1 |
| Subnet | `subnet-` | 4 |
| Internet gateway | `igw-` | 1 |
| Elastic IP | `eipalloc-` | 1 |
| NAT gateway | `nat-` | 1 |
| Route table | `rtb-` | 3 |
| Route | *(none)* | 3 |
| Route table association | `rtbassoc-` | 4 |
| Security group | `sg-` | 2 |

**NOT resources** — settings inside the above: `10.0.0.0/16`, `10.0.0.0/20`,
port 22, port 8080, `0.0.0.0/0`, `enable_dns_support = true`, `ap-south-1a`.

---

## 8. Blocks written vs things created

These differ, because `count` and `for_each` multiply.

| Module | Blocks written | Resources created |
|---|---|---|
| vpc | 14 | ~20 |
| ecr | 2 | 6 (3 repos + 3 lifecycle policies, via `for_each`) |
| iam | 6 | 6 |
| eks | 21 | 21 |
| bootstrap | 6 | 6 |

**`count` vs `for_each`:** count gives a list indexed by position, so removing a
middle item renumbers everything after it and Terraform destroys and recreates
them. for_each gives a map keyed by name, so removing one leaves the others
alone. Subnets use count because they're interchangeable; ECR repos use for_each
so deleting `admin` doesn't disturb `frontend`.

---

## 9. Two surprises in my own EKS module

**There is no `aws_instance` anywhere in the codebase.** I never write one. I
write `aws_eks_node_group`, and AWS launches the EC2 instances itself.
`desired_size = 2` is the only place the number appears. That's what "managed"
node group means.

**Memory isn't a setting at all.** It's implied by
`instance_types = ["t3.medium"]` — 2 vCPU, 4 GB. Same as choosing t2.micro in the
console; the instance type defines the memory.

**16 of 49 blocks are IAM**, and 10 of those are one-line policy attachments.

---

## 10. Viva answer — "why 14 VPC resources?"

Don't say "I chose 14." Say:

> I didn't pick a number. I decided two things: public and private subnets,
> across two availability zones. Everything else follows.
>
> A VPC needs subnets or nothing can live in it. Subnets need route tables or
> traffic has nowhere to go. Public subnets need an internet gateway. Private
> subnets need a NAT gateway, which needs an elastic IP. Each subnet needs a
> route table association. That's twenty resources before a single optional
> decision.

Then name the three that **were** decisions:

- **Two AZs, not one** — EKS refuses to create a cluster with subnets in a
  single AZ. A hard requirement, not a preference.
- **One NAT gateway, not one per AZ** — ~$32/month each. One per AZ is the
  common tutorial default and triples the cost for no benefit in dev. The code
  supports either via `single_nat_gateway`.
- **Private subnets at all** — nodes could sit in public subnets with no NAT.
  Cheaper, but every worker node would be directly reachable from the internet.

**If asked "could you do it with fewer?"** — yes: one AZ, no private subnets, no
NAT, around eight resources. It wouldn't run EKS, because of the two-AZ rule.

The pattern that scores: **separate what AWS required from what I decided**, and
have a reason for each decision.

---

## The four things to remember

1. A resource is anything with its own AWS ID — not just servers.
2. Ports and CIDRs are settings inside resources, not resources.
3. Variables are only for values that might genuinely differ; most settings come
   from other resources or are deliberately fixed.
4. Route tables decide *where traffic goes*; security groups decide *whether
   it's allowed*. Both must agree.
