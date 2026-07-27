# Bootstrap - Terraform remote state

Run this **once per AWS account**, before anything in `envs/`.

```bash
cd bootstrap
terraform init
terraform apply
```

Then copy the outputs into `../envs/dev/backend.hcl`:

```
state_bucket_name = shopnow-tfstate-968313778667
lock_table_name   = shopnow-tf-locks
```

## Why is this a separate stack?

The S3 backend cannot store the state of the bucket that *is* the backend -
a chicken-and-egg problem. So this small stack keeps its state in a local
`terraform.tfstate` file, which is committed nowhere and only ever needs to
run again if the bucket changes.

## Do not destroy this

`terraform destroy` here would delete the state of every other stack.
`force_destroy = false` on the bucket makes that fail unless you empty it
first, which is deliberate.
