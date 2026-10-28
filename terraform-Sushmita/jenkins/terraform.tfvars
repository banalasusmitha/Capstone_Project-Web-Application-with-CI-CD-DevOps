# Jenkins server values. Safe to commit - no secrets.

# Everyone who needs SSH or the Jenkins UI. Re-check with: curl ifconfig.me
admin_cidrs = [
  "116.73.141.79/32", # Susmitha
  # "x.x.x.x/32",     # Kaushik  - remove the # and put his IP
  # "x.x.x.x/32",     # Avinash
  # "x.x.x.x/32",     # Ravi
]

# GitHub's webhook senders, port 8080 only, so a push to GitHub triggers the
# pipeline instantly (the pipeline also polls every 5 min as a fallback).
# IPv4 "hooks" list from https://api.github.com/meta, checked 28 Oct 2026.
webhook_cidrs = [
  "192.30.252.0/22",
  "185.199.108.0/22",
  "140.82.112.0/20",
  "143.55.64.0/20",
  "9.234.106.48/28",
  "9.234.98.160/28",
  "9.234.98.176/28",
]

# Same public key as the CI agent, so one private key (~/.ssh/shopnow-ci-agent)
# opens both machines.
public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6/RlP7Ef0nb63r85z0AgkS6GwiudbkDQRN0yU3EufU shopnow-ci-agent"

instance_type = "t3.medium"
