# Why the same filenames appear in every folder

The confusing thing about this project is that `main.tf`, `variables.tf` and
`outputs.tf` appear three times, in three folders, containing completely
different things. This document takes those filenames one at a time and shows
you the actual contents side by side.

---

## First: Terraform does not care about filenames

This is the single fact that makes everything else click.

When you run `terraform apply` in a folder, Terraform reads **every `.tf` file
in that folder and glues them together into one big configuration**. It does not
look for a file called `main.tf`. It does not run `variables.tf` first. You
could put all 200 lines in a single file called `zebra.tf` and it would behave
identically.

So the three-file split is **purely a convention for humans**. Everyone in the
industry uses it, so anyone can open your folder and know where to look:

| Filename | What people expect to find |
|----------|---------------------------|
| `variables.tf` | the inputs this folder accepts |
| `main.tf` | the resources this folder creates |
| `outputs.tf` | the values this folder hands back |

The reason it *feels* repetitive is that you have three folders that each need
all three roles. Same three job titles, three different departments.

---

## Second: there are only two kinds of folder

| Kind | Which folders | Who calls it |
|------|--------------|--------------|
| **Root module** - you `cd` into it and run `terraform apply` | `bootstrap/`, `envs/dev/` | you, from your terminal |
| **Child module** - a reusable component, never run directly | `modules/vpc`, `modules/ecr`, `modules/iam`, `modules/eks` | called by `envs/dev/main.tf` |

You will never `cd modules/vpc && terraform apply`. That folder has no region,
no CIDR, no cluster name - it is a recipe with blanks in it. `envs/dev` fills
the blanks in.

---

## Now the comparison: `main.tf` in three folders

### `bootstrap/main.tf` - creates real things, hard-coded on purpose

```hcl
resource "aws_s3_bucket" "tf_state" {
  bucket        = local.bucket_name
  force_destroy = false
  tags = { Name = local.bucket_name }
}

resource "aws_dynamodb_table" "tf_lock" {
  count        = var.create_dynamodb_lock_table ? 1 : 0
  name         = "${var.project}-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  ...
}
```

Real AWS resources. Notice it also contains its own `terraform {}` and
`provider "aws" {}` blocks at the top - because it is a **root module**, it must
declare which providers it uses and which region it works in. Nothing above it
does that for it.

### `modules/vpc/main.tf` - creates real things, but every value is a blank

```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(var.tags, { Name = "${var.name}-vpc" })
}
```

Also a `resource` block, so it looks similar. The difference is that **every
interesting value is `var.something`**. There is no `10.0.0.0/16` anywhere in
this file, and no `provider` block either - a child module inherits the provider
from whoever called it.

That is what makes it reusable. `envs/dev` and a future `envs/prod` can both
call this file with different CIDRs.

### `envs/dev/main.tf` - creates nothing at all

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name         = local.name
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  az_count     = var.az_count
  tags         = local.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  ...
}
```

**Open this file and search for the word `resource`. There isn't one.** Not a
single AWS resource is declared here. It contains only `locals` and four
`module` blocks.

This is the wiring diagram. `source` says which folder to run,
and everything after it is the values being passed in.

Look closely at the EKS block:

```hcl
public_subnet_ids = module.vpc.public_subnet_ids
```

That reads: *take the output called `public_subnet_ids` from the module I named
`vpc`, and feed it into the input called `public_subnet_ids` on the EKS module.*
This one line is how the VPC module and the EKS module get connected - and it is
also how Terraform works out that the VPC must be built before the cluster.

**The three `main.tf` files summarised:**

| Folder | Contains | Has a `provider` block? |
|--------|----------|------------------------|
| `bootstrap/main.tf` | `resource` blocks with concrete values | yes |
| `modules/vpc/main.tf` | `resource` blocks where values are `var.*` | no |
| `envs/dev/main.tf` | `module` blocks only, zero resources | yes (in `versions.tf`) |

---

## Now `variables.tf` in two folders

### `modules/vpc/variables.tf` - "what I need in order to work"

```hcl
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  description = "EKS cluster name (used for the kubernetes.io/cluster subnet tags)."
  type        = string
}
```

`vpc_cidr` has a `default`, so the caller may omit it. `cluster_name` has no
default, so it is **required** - Terraform errors immediately if `envs/dev`
forgets to pass it.

### `envs/dev/variables.tf` - "what the whole environment accepts"

```hcl
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}
```

Nearly identical - and that is the part that looks like pointless duplication.
It is not. These are two different scopes:

```
envs/dev/variables.tf     declares  var.vpc_cidr    (environment level)
                                        │
envs/dev/main.tf          passes    vpc_cidr = var.vpc_cidr
                                        │
                                        ▼
modules/vpc/variables.tf  declares  var.vpc_cidr    (module level)
modules/vpc/main.tf       uses      cidr_block = var.vpc_cidr
```

Same as a function parameter in code. A variable in one function is not
automatically visible inside another - it has to be passed in, and the receiving
function has to declare that it accepts it. The module cannot reach up and grab
values from its caller.

---

## Now `outputs.tf` in two folders

### `modules/vpc/outputs.tf` - "here is what I made, for my caller"

```hcl
output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}
```

This exists so that `envs/dev/main.tf` can write
`module.vpc.public_subnet_ids`. Without this output block, that value would be
locked inside the module and invisible - even though the subnets exist.

**If a module doesn't declare an output, the value does not leave the module.**
That is the rule people forget.

### `envs/dev/outputs.tf` - "here is what I made, for a human"

```hcl
output "jenkins_instance_profile_name" {
  description = "Attach this instance profile to the Jenkins EC2 instance."
  value       = module.iam.jenkins_instance_profile_name
}
```

Nothing calls `envs/dev` - it is the top of the chain. So these outputs are what
gets printed to your terminal when you run `terraform output`, which is how you
hand values to Kaushik and Avinash.

Notice the relay: the IAM module outputs a value, and `envs/dev` re-outputs the
same value one level higher so a person can see it.

```
modules/iam/outputs.tf   ──►   envs/dev/outputs.tf   ──►   your terminal
```

---

## The four files that exist only in `envs/dev/`

These have no equivalent in the modules, which is why they look odd.

### `terraform.tfvars` - the values

`variables.tf` says *what may be set and what type it is*. `terraform.tfvars`
says *what it actually is for this environment*:

```hcl
aws_region   = "ap-south-1"
cluster_name = "shopnow-eks-dev"
capacity_type = "SPOT"
desired_size  = 2
```

Terraform loads this file automatically - you never reference it anywhere.
**This is the only file you normally edit.** A future `envs/prod` would have the
same `variables.tf` and a different `terraform.tfvars`.

Think of `variables.tf` as the form and `terraform.tfvars` as the filled-in form.

### `versions.tf` - version pins and the provider

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.60.0, < 7.0.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = { Project = ..., Owner = ... } }
}
```

Two jobs. It stops a teammate on a different Terraform version producing a
different result, and it configures the AWS provider once for every module
underneath. Child modules inherit this - that is why `modules/vpc` has no
`provider` block and no notion of region.

### `backend.tf` - where state lives

```hcl
terraform {
  backend "s3" {}
}
```

Deliberately empty. Backend blocks cannot use variables, because Terraform has
to find the state file before it can evaluate anything. So the values live in a
separate file passed at init time.

### `backend.hcl` - the actual bucket

```hcl
bucket = "shopnow-tfstate-968313778667"
key    = "dev/terraform.tfstate"
region = "ap-south-1"
```

Used as `terraform init -backend-config=backend.hcl`. This is what lets
`envs/prod` point at a different bucket without changing a line of code.

---

## One value's full journey

Follow `vpc_cidr` from where you type it to where AWS receives it. Five files:

```
1. envs/dev/terraform.tfvars       vpc_cidr = "10.0.0.0/16"
                                        │  you set the value here
2. envs/dev/variables.tf           variable "vpc_cidr" { type = string }
                                        │  the environment declares it exists
3. envs/dev/main.tf                module "vpc" { vpc_cidr = var.vpc_cidr }
                                        │  passed into the module
4. modules/vpc/variables.tf        variable "vpc_cidr" { type = string }
                                        │  the module declares it accepts it
5. modules/vpc/main.tf             resource "aws_vpc" "this" {
                                     cidr_block = var.vpc_cidr
                                   }
                                        │
                                        ▼  AWS creates the VPC
```

Five files for one value seems heavy for a project this size. The payoff arrives
when you add a second environment: steps 4 and 5 are shared, so `dev` and `prod`
are guaranteed to be built the same way and can never silently drift apart. That
guarantee is the entire reason the industry writes Terraform like this.

---

## Which file do I edit when...

| I want to... | Edit |
|--------------|------|
| change the region, cluster name, node size, instance count | `envs/dev/terraform.tfvars` |
| allow a new setting to be configurable | `envs/dev/variables.tf`, then pass it in `envs/dev/main.tf`, then declare it in the module's `variables.tf` |
| add a new AWS resource (say, an S3 bucket for uploads) | the relevant `modules/*/main.tf`, or a new module |
| expose a value to my teammates | the module's `outputs.tf`, then `envs/dev/outputs.tf` |
| point at a different state bucket | `envs/dev/backend.hcl` |
| pin a different provider version | `envs/dev/versions.tf` |

Day to day, you will edit exactly one file: `terraform.tfvars`. That is the sign
the structure is working.

---

## The one-sentence version, if you are asked in the viva

> `modules/` says *how* to build each piece and contains no real values;
> `envs/dev/` supplies the values and wires the pieces together; `bootstrap/`
> creates the S3 bucket that stores the state for everything else. Inside each
> folder, `variables.tf` is the inputs, `main.tf` is the work, and `outputs.tf`
> is what comes back out.
