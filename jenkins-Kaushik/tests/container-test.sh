#!/usr/bin/env bash
###############################################################################
# container-test.sh - tests the three freshly built images BEFORE they are
# pushed to ECR. Runs them together on a private Docker network, exactly as
# they talk to each other in Kubernetes (frontend/admin nginx proxy to
# "backend-service"), and checks:
#   1. backend  /api/health answers 200
#   2. frontend /health and admin /health answer 200
#   3. the React bundles were built for the right path (USER_NAME), i.e.
#      index.html references /<user>/ and /<user>-admin/ - the classic
#      "everything 404s behind the ingress" bug is caught here, not on EKS
#   4. the frontend nginx proxies /api/ through to the backend
#   5. the backend container does not run as root
#
# Usage: container-test.sh <registry/namespace> <tag> <user_name>
###############################################################################
set -euo pipefail

PREFIX="$1"   # e.g. 095355901688.dkr.ecr.ap-south-1.amazonaws.com/avinash-shopnow
TAG="$2"
USER_NAME="$3"

NET="shopnow-test-${TAG}-$$"
CURL_IMG="curlimages/curl:8.10.1"
fail=0

cleanup() {
  docker rm -f "be-${NET}" "fe-${NET}" "ad-${NET}" >/dev/null 2>&1 || true
  docker network rm "${NET}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

curl_in_net() { docker run --rm --network "${NET}" "${CURL_IMG}" -s --max-time 5 "$@"; }

check() {   # check <description> <command...>
  local desc="$1"; shift
  if "$@"; then echo "PASS  ${desc}"; else echo "FAIL  ${desc}"; fail=1; fi
}

wait_http() {  # wait_http <url> - up to 60s
  local i
  for i in $(seq 1 30); do
    [[ "$(curl_in_net -o /dev/null -w '%{http_code}' "$1" || true)" == "200" ]] && return 0
    sleep 2
  done
  return 1
}

docker network create "${NET}" >/dev/null

# Backend starts without MongoDB (it logs a connection error and keeps serving /api/health).
docker run -d --name "be-${NET}" --network "${NET}" --network-alias backend-service \
  -e MONGODB_URI="mongodb://127.0.0.1:1/none" "${PREFIX}/backend:${TAG}" >/dev/null
docker run -d --name "fe-${NET}" --network "${NET}" --network-alias frontend "${PREFIX}/frontend:${TAG}" >/dev/null
docker run -d --name "ad-${NET}" --network "${NET}" --network-alias admin    "${PREFIX}/admin:${TAG}" >/dev/null

check "backend  /api/health returns 200"  wait_http "http://backend-service:5000/api/health"
check "frontend /health returns 200"      wait_http "http://frontend/health"
check "admin    /health returns 200"      wait_http "http://admin/health"

check "frontend index.html built for /${USER_NAME}" \
  bash -c "curl_out=\$(docker run --rm --network ${NET} ${CURL_IMG} -s --max-time 5 http://frontend/); grep -q '/${USER_NAME}/' <<<\"\$curl_out\""
check "admin index.html built for /${USER_NAME}-admin" \
  bash -c "curl_out=\$(docker run --rm --network ${NET} ${CURL_IMG} -s --max-time 5 http://admin/); grep -q '/${USER_NAME}-admin/' <<<\"\$curl_out\""

check "frontend proxies /api/health to backend" \
  bash -c "docker run --rm --network ${NET} ${CURL_IMG} -s --max-time 5 http://frontend/api/health | grep -q 'OK'"

check "backend runs as non-root user" \
  bash -c "[ \"\$(docker exec be-${NET} id -u)\" != '0' ]"

if [[ $fail -ne 0 ]]; then
  echo "--- backend logs";  docker logs --tail 30 "be-${NET}" || true
  echo "--- frontend logs"; docker logs --tail 30 "fe-${NET}" || true
  echo "--- admin logs";    docker logs --tail 30 "ad-${NET}" || true
  echo "Container tests FAILED"
  exit 1
fi
echo "All container tests passed"
