# ShopNow Kubernetes Configuration

This folder contains the Kubernetes manifests for deploying the ShopNow MERN application.

## Files

- frontend-deployment.yaml: Runs two frontend application pods with health probes and resource limits.
- backend-deployment.yaml: Runs two backend pods and connects them to MongoDB using MONGODB_URI.
- admin-deployment.yaml: Runs two admin dashboard pods with health probes and resource limits.
- frontend-service.yaml: Exposes the frontend inside the cluster on port 80.
- backend-service.yaml: Exposes the backend inside the cluster on port 5000.
- admin-service.yaml: Exposes the admin dashboard inside the cluster on port 80.
- mongodb.yaml: Creates MongoDB StatefulSet, headless Service and persistent 5Gi storage.
- ingress.yaml: Routes /avinash to the frontend and /avinash-admin to the admin dashboard.
- hpa.yaml: Automatically scales the backend between two and four pods based on 70% CPU utilization.

## Prerequisites

- Kubernetes cluster and kubectl access.
- EBS CSI driver and gp3 StorageClass.
- NGINX Ingress Controller.
- Metrics Server for HPA.
- Access to the ShopNow images in AWS ECR.

## Deployment order

Run commands from the repository root.

1. Apply MongoDB:

   kubectl apply -f kubernetes-Avinash/mongodb.yaml

2. Wait for MongoDB:

   kubectl rollout status statefulset/mongodb

3. Apply application Services and Deployments:

   kubectl apply -f kubernetes-Avinash/frontend-service.yaml
   kubectl apply -f kubernetes-Avinash/backend-service.yaml
   kubectl apply -f kubernetes-Avinash/admin-service.yaml

   kubectl apply -f kubernetes-Avinash/frontend-deployment.yaml
   kubectl apply -f kubernetes-Avinash/backend-deployment.yaml
   kubectl apply -f kubernetes-Avinash/admin-deployment.yaml

4. Apply Ingress and HPA:

   kubectl apply -f kubernetes-Avinash/ingress.yaml
   kubectl apply -f kubernetes-Avinash/hpa.yaml

5. Verify resources:

   kubectl get pods,svc,pvc,hpa,ingress

## Application health endpoints

- Frontend: /health on port 80
- Admin: /health on port 80
- Backend: /api/health on port 5000

## MongoDB connection

mongodb://mongodb-0.mongodb-service:27017/shopnow
