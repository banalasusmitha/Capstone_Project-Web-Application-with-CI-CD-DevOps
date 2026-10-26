# Jenkins server values. Safe to commit - no secrets.

# Everyone who needs SSH or the Jenkins UI. Re-check with: curl ifconfig.me
admin_cidrs = [
  "116.73.141.79/32", # Susmitha
]

# Same public key as the CI agent, so one private key (~/.ssh/shopnow-ci-agent)
# opens both machines.
public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6/RlP7Ef0nb63r85z0AgkS6GwiudbkDQRN0yU3EufU shopnow-ci-agent"

instance_type = "t3.medium"
