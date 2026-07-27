# App integration - what ShopNow actually needs from the infrastructure

Read from the application source at
`https://github.com/banalasusmitha/shopNow`. Everything below was verified
against the real `Dockerfile`, `nginx/default.conf` and `server.js` files,
not assumed.

---

## The four workloads

| Service  | Image base        | Container port | Health path      | Notes |
|----------|-------------------|----------------|------------------|-------|
| frontend | nginx:1.24-alpine | 80             | `/health`        | React SPA built at image-build time |
| admin    | nginx:1.24-alpine | 80             | `/health`        | React SPA built at image-build time |
| backend  | node:18-alpine    | 5000           | `/api/health`    | Express + Mongoose, runs as non-root `appuser` |
| mongodb  | mongo (Docker Hub)| 27017          | -                | StatefulSet + PVC, needs a StorageClass |

`/health` on the two nginx images is a static 200 defined in their
`nginx/default.conf`. The backend has **no** `/health` route - only `/` and
`/api/health`.

---

## The `USER_NAME` value ties everything together

`frontend/Dockerfile` and `admin/Dockerfile` both contain:

```dockerfile
ARG USER_NAME=aryan
ENV PUBLIC_URL=/${USER_NAME}
ENV REACT_APP_API_BASE_URL=/${USER_NAME}/api
RUN npm run build
```

This is baked into the **static bundle at build time** - it cannot be changed
by a Kubernetes env var afterwards. It decides three things that must match:

1. the ingress path (`/avinash`, `/avinash-admin`)
2. the asset URLs inside `index.html`
3. the API base URL the React app calls

Terraform exposes it as `app_user_name` (default `avinash`, matching the
images already in ECR) and outputs it:

```bash
terraform output app_ingress_paths
terraform output docker_build_args     # --build-arg USER_NAME=avinash
```

Jenkins must pass it, or the frontend loads at `/aryan` and 404s:

```bash
docker build --build-arg USER_NAME=avinash \
  -t $ECR/avinash-shopnow/frontend:$BUILD_NUMBER frontend/
```

---

## What Terraform provisions for the app

| App requirement | Provided by |
|-----------------|-------------|
| Somewhere to push images | `modules/ecr` - `avinash-shopnow/{frontend,admin,backend}` |
| Nodes able to pull those images | `AmazonEC2ContainerRegistryReadOnly` on the node role (`modules/eks`) |
| Persistent volume for MongoDB | `aws-ebs-csi-driver` add-on with an IRSA role + `extras/storageclass-gp3.yaml` |
| HPA / `kubectl top` | `metrics-server` add-on |
| Internet-facing load balancer for the NGINX ingress | Public subnets tagged `kubernetes.io/role/elb=1` |
| Outbound internet for nodes (npm, Docker Hub, ECR) | NAT Gateway + private route tables |
| Jenkins able to push and deploy | Instance profile + EKS Access Entry (`modules/iam`, `modules/eks`) |

### You do NOT need an ECR imagePullSecret

The upstream README tells you to run:

```bash
kubectl create secret docker-registry ecr-secret --docker-password=$(aws ecr get-login-password ...)
```

Skip it. That token expires after 12 hours and your pods will start failing
with `ImagePullBackOff` the next morning. Because the node IAM role already
carries `AmazonEC2ContainerRegistryReadOnly`, the kubelet pulls from ECR
natively. That is worth stating in the viva - it is a genuine improvement over
the reference instructions.

### EBS CSI driver: IRSA instead of the console

The upstream README walks through installing the EBS CSI driver by clicking
through the EKS console with Pod Identity. Terraform does it with an IRSA role
(`aws_iam_role.ebs_csi` in `modules/eks`), so it is reproducible and survives a
`destroy` / `apply` cycle.

---

## MongoDB connection string

The backend reads `MONGODB_URI` and falls back to `mongodb://localhost:27017/shopnow`,
which is wrong inside Kubernetes. It must be set explicitly. For a StatefulSet
named `mongodb` with a headless service `mongodb-service`:

```yaml
env:
  - name: MONGODB_URI
    value: "mongodb://mongodb-0.mongodb-service:27017/shopnow"
```

The backend seeds six sample products on first connect, so an empty database is
expected and fine.

---

## Three app-level issues worth flagging to the team

These are not infrastructure problems, but they will look like infrastructure
problems when the pods misbehave.

**1. `backend/Dockerfile` health check hits a route that does not exist.**

```dockerfile
CMD wget -qO- http://127.0.0.1:${PORT}/health || exit 1
```

`server.js` defines `/` and `/api/health`, not `/health`, so this always
returns 404. Harmless in Kubernetes (kubelet uses the probes in the manifest,
not the Docker HEALTHCHECK) but the readiness probe must use `/api/health`:

```yaml
readinessProbe:
  httpGet:
    path: /api/health
    port: 5000
```

**2. `admin/nginx/default.conf` has no `/api/` proxy block.**

The admin React app calls `${REACT_APP_API_BASE_URL}/invoices`, which resolves
to `/avinash-admin/api/invoices`. The admin nginx config only proxies
`location /admin/`, which the backend does not serve. Every admin API call will
fall through to the SPA fallback and return `index.html`, so the dashboard shows
empty data with a JSON parse error in the console. It needs the same block the
frontend has:

```nginx
location /api/ {
    proxy_pass http://backend-service:5000/api/;
}
```

**3. The backend CORS allow-list is localhost-only.**

```js
origin: ['http://localhost:3000', 'http://localhost:3001']
```

This is fine as long as browsers only ever reach the API *through* the nginx
proxy in the frontend/admin pods, which makes it same-origin. If anyone adds an
ingress rule that exposes `backend-service` directly, the browser will start
blocking calls and it will look like a networking failure.

---

## Also missing from the app fork

The upstream README references `kubernetes/`, `scripts/` and `jenkins/`
directories that are not present in this fork - only `frontend/`, `admin/`,
`backend/` and `docs/` were copied. That is why Avinash wrote the manifests in
`kubernetes-Avinash/` by hand. Nothing to fix, just do not go looking for files
the README promises.
