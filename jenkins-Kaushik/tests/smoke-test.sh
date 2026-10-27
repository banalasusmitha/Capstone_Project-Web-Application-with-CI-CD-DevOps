#!/usr/bin/env bash
###############################################################################
# smoke-test.sh - post-deployment tests against the live EKS deployment.
#
# In-cluster (from a throwaway curl pod, so it works without an ingress):
#   - backend  /api/health                       -> 200
#   - backend  /api/products                     -> 200 + JSON (proves MongoDB works)
#   - frontend /health, admin /health            -> 200
# From the internet, through the NGINX ingress load balancer:
#   - /<user>/ and /<user>-admin/                -> 200
#   - /<user>/api/health                         -> 200
#
# Exit codes: 0 all passed, 1 in-cluster failure (app is broken),
#             3 in-cluster OK but external access failed / no ingress (UNSTABLE)
#
# Usage: smoke-test.sh <namespace> <user_name>
###############################################################################
set -uo pipefail

NS="${1:-default}"
USER_NAME="${2:-avinash}"
POD="smoke-test-$RANDOM"
fail=0
ext_fail=0

pass() { echo "PASS  $*"; }
bad()  { echo "FAIL  $*"; }

kubectl run "$POD" -n "$NS" --image=curlimages/curl:8.10.1 --restart=Never \
  --command -- sleep 300 >/dev/null
trap 'kubectl delete pod "$POD" -n "$NS" --now >/dev/null 2>&1 || true' EXIT
kubectl wait --for=condition=Ready "pod/$POD" -n "$NS" --timeout=120s >/dev/null

incluster() {  # incluster <url> -> prints "<code> <body>"
  kubectl exec -n "$NS" "$POD" -- curl -s --max-time 10 -w ' HTTP%{http_code}' "$1" 2>/dev/null
}

check_incluster() {  # check_incluster <desc> <url> [body-regex]
  local out code
  for _ in 1 2 3 4 5 6; do          # pods may still be warming up - retry for ~1 min
    out="$(incluster "$2")"; code="${out##*HTTP}"
    [[ "$code" == "200" ]] && break
    sleep 10
  done
  if [[ "$code" == "200" && ( -z "${3:-}" || "$out" =~ $3 ) ]]; then
    pass "$1"
  else
    bad "$1 (HTTP $code) ${out:0:200}"; fail=1
  fi
}

echo "=== In-cluster checks (namespace $NS)"
check_incluster "backend  /api/health"        "http://backend-service:5000/api/health" '"status"'
check_incluster "backend  /api/products (DB)" "http://backend-service:5000/api/products" '^[[{]'
check_incluster "frontend /health"            "http://frontend-service/health"
check_incluster "admin    /health"            "http://admin-service/health"

echo "=== External checks through the ingress load balancer"
HOST="$(kubectl get ingress -n "$NS" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
if [[ -z "$HOST" ]]; then
  # A new AWS load balancer needs a few minutes to get its address.
  if kubectl get ingress -n "$NS" -o name 2>/dev/null | grep -q .; then
    echo "Ingress exists, waiting up to 5 min for its load balancer address..."
    for _ in $(seq 1 30); do
      HOST="$(kubectl get ingress -n "$NS" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')"
      [[ -n "$HOST" ]] && break; sleep 10
    done
  fi
fi

if [[ -z "$HOST" ]]; then
  bad "no Ingress / load balancer address in namespace $NS - app is not reachable from the internet"
  ext_fail=1
else
  echo "Load balancer: http://$HOST"
  for path in "/${USER_NAME}/" "/${USER_NAME}-admin/" "/${USER_NAME}/api/health"; do
    code=000
    for _ in $(seq 1 18); do     # DNS for a new load balancer can take a few minutes
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$HOST$path" || true)"
      [[ "$code" == "200" ]] && break; sleep 10
    done
    if [[ "$code" == "200" ]]; then pass "GET $path"; else bad "GET $path (HTTP $code)"; ext_fail=1; fi
  done
  echo "APP_URL=http://$HOST/${USER_NAME}/"
  echo "ADMIN_URL=http://$HOST/${USER_NAME}-admin/"
fi

if [[ $fail -ne 0 ]]; then echo "Smoke tests FAILED"; exit 1; fi
if [[ $ext_fail -ne 0 ]]; then echo "In-cluster OK, external access FAILED"; exit 3; fi
echo "All smoke tests passed"
