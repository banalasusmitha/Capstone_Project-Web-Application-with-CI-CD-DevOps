#!/usr/bin/env bash
###############################################################################
# install-jenkins.sh - turns the Terraform-built Jenkins EC2 (Amazon Linux 2023)
# into the ShopNow CI/CD server.                                    (Sprint 1)
#
# Installs:  Jenkins LTS (Java 21), Docker, Terraform, kubectl, Helm,
#            Ansible (+ amazon.aws collection), AWS CLI v2, jq
# Configures: plugins (plugins.txt), admin user, security and the three
#            pipeline jobs from casc/jenkins.yaml (Configuration as Code)
#
# AWS access comes from the server's IAM instance profile (terraform-Sushmita/
# jenkins). No access keys are created or stored anywhere.
#
# Usage (on the server, from a clone of the capstone repo):
#   sudo bash jenkins-Kaushik/server/install-jenkins.sh [--branch main]
#
# Safe to re-run: every step checks before it changes anything.
###############################################################################
set -euo pipefail

BRANCH="main"
REPO="https://github.com/banalasusmitha/Capstone_Project-Web-Application-with-CI-CD-DevOps.git"
K8S_MINOR="1.36"   # match kubernetes_version in terraform-Sushmita/envs/dev

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --repo)   REPO="$2";   shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_HOME="/var/lib/jenkins"
CASC_DIR="${JENKINS_HOME}/casc"
ENV_FILE="/etc/sysconfig/jenkins-casc"
CLI_JAR="/opt/jenkins-cli.jar"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
grep -q 'Amazon Linux' /etc/os-release || warn "Written for Amazon Linux 2023 - other distros may need changes."

###############################################################################
log "1/9 Base packages"
dnf -y install java-21-amazon-corretto-headless git docker jq unzip tar \
  fontconfig dnf-plugins-core openssl

###############################################################################
log "2/9 Swap (React builds + Jenkins on a 4 GiB t3.medium run out of memory without it)"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

###############################################################################
log "3/9 Jenkins LTS"
if ! rpm -q jenkins >/dev/null 2>&1; then
  curl -fsSL -o /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
  # Jenkins rotates its signing key; import whichever ones exist.
  for key in jenkins.io-2026.key jenkins.io-2023.key; do
    rpm --import "https://pkg.jenkins.io/redhat-stable/${key}" 2>/dev/null || true
  done
  dnf -y install jenkins
fi

###############################################################################
log "4/9 Docker"
systemctl enable --now docker
usermod -aG docker jenkins

###############################################################################
log "5/9 Terraform, kubectl ${K8S_MINOR}, Helm"
if ! command -v terraform >/dev/null; then
  dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
  dnf -y install terraform
fi

if ! command -v kubectl >/dev/null || ! kubectl version --client 2>/dev/null | grep -q "v${K8S_MINOR}"; then
  KVER="$(curl -fsSL "https://dl.k8s.io/release/stable-${K8S_MINOR}.txt")"
  curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi

if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | HELM_INSTALL_DIR=/usr/local/bin bash
fi

command -v aws >/dev/null || dnf -y install awscli-2

###############################################################################
log "6/9 Ansible (runs Ravi's playbook from the 2-config-ansible job)"
# AL2023's default python3 is 3.9, too old for current ansible-core; use 3.11.
dnf -y install python3.11 python3.11-pip
if ! command -v ansible-playbook >/dev/null; then
  python3.11 -m pip install --quiet ansible-core boto3 botocore
fi
GALAXY="$(command -v ansible-galaxy || echo /usr/local/bin/ansible-galaxy)"
# Collections go into the jenkins user's home so pipeline runs find them.
sudo -u jenkins -H "${GALAXY}" collection install \
  amazon.aws community.general community.docker ansible.posix >/dev/null

###############################################################################
log "7/9 Configuration as Code"
mkdir -p "${CASC_DIR}"
cp "${SCRIPT_DIR}/casc/jenkins.yaml" "${CASC_DIR}/jenkins.yaml"

# Admin password: generated once, kept on the server only.
if [[ ! -s "${CASC_DIR}/admin-password" ]]; then
  openssl rand -base64 18 | tr -d '/+=' > "${CASC_DIR}/admin-password"
fi
chmod 600 "${CASC_DIR}/admin-password"
ADMIN_PW="$(cat "${CASC_DIR}/admin-password")"

# Public IP via IMDSv2 (the instance requires tokens).
TOKEN="$(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' || true)"
PUBLIC_IP="$(curl -fsS -H "X-aws-ec2-metadata-token: ${TOKEN}" http://169.254.169.254/latest/meta-data/public-ipv4 || echo localhost)"

cat > "${ENV_FILE}" <<EOF
JENKINS_ADMIN_PASSWORD=${ADMIN_PW}
JENKINS_PUBLIC_URL=http://${PUBLIC_IP}:8080/
CAPSTONE_REPO=${REPO}
CAPSTONE_BRANCH=${BRANCH}
EOF
chmod 600 "${ENV_FILE}"
chown -R jenkins:jenkins "${CASC_DIR}"

mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
EnvironmentFile=${ENV_FILE}
Environment="CASC_JENKINS_CONFIG=${CASC_DIR}/jenkins.yaml"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Xmx1g"
Environment="AWS_DEFAULT_REGION=ap-south-1"
EOF
systemctl daemon-reload

###############################################################################
log "8/9 Start Jenkins and install plugins"
wait_for_jenkins() {
  local i
  for i in $(seq 1 60); do
    code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login || true)"
    [[ "$code" == "200" ]] && return 0
    sleep 5
  done
  echo "Jenkins did not come up in 5 minutes - check: journalctl -u jenkins -n 100"; exit 1
}

systemctl enable jenkins
systemctl restart jenkins
wait_for_jenkins

curl -fsSL -o "${CLI_JAR}" http://localhost:8080/jnlpJars/jenkins-cli.jar

# First run: no security realm yet (JCasC plugin not installed) so the CLI needs
# no login. Later runs: JCasC has created the admin user.
cli() {
  if java -jar "${CLI_JAR}" -s http://localhost:8080/ -auth "admin:${ADMIN_PW}" who-am-i >/dev/null 2>&1; then
    java -jar "${CLI_JAR}" -s http://localhost:8080/ -auth "admin:${ADMIN_PW}" "$@"
  else
    java -jar "${CLI_JAR}" -s http://localhost:8080/ "$@"
  fi
}

# Make sure update-center data is downloaded before installing.
echo 'jenkins.model.Jenkins.instance.updateCenter.updateAllSites()' | cli groovy = >/dev/null

failed=()
while read -r plugin; do
  [[ -z "$plugin" || "$plugin" == \#* ]] && continue
  if cli install-plugin "$plugin" >/dev/null 2>&1; then
    echo "  installed: $plugin"
  else
    failed+=("$plugin"); warn "could not install: $plugin"
  fi
done < "${SCRIPT_DIR}/plugins.txt"

###############################################################################
log "9/9 Restart so Configuration as Code applies (admin user + jobs)"
systemctl restart jenkins
wait_for_jenkins

if curl -fsS -u "admin:${ADMIN_PW}" http://localhost:8080/whoAmI/api/json | grep -q '"authenticated":true'; then
  echo "  admin login OK"
else
  warn "admin login failed - check: journalctl -u jenkins | grep -i casc"
fi

cat <<EOF

=====================================================================
 Jenkins is ready:   http://${PUBLIC_IP}:8080/
 User:               admin
 Password:           sudo cat ${CASC_DIR}/admin-password
 Jobs branch:        ${BRANCH}   (re-run with --branch main after merge)

 Tool versions:
   $(java -version 2>&1 | head -1)
   $(docker --version)
   $(terraform -version | head -1)
   kubectl $(kubectl version --client -o json | jq -r .clientVersion.gitVersion)
   $(helm version --short)
   $(ansible --version | head -1)
   $(aws --version)

 Next: add the CI-agent SSH key as credential 'ci-agent-ssh'
       (docs-Kaushik/setup-guide.md, step 4)
=====================================================================
EOF
[[ ${#failed[@]} -eq 0 ]] || warn "Plugins that failed (install from Manage Jenkins > Plugins): ${failed[*]}"
