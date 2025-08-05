# Kubernetes Nginx Application with ArgoCD

This repository contains a complete implementation of a Kubernetes-based nginx application deployed using ArgoCD for GitOps continuous deployment.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                 │    │                 │
│   Git Repository │───▶│     ArgoCD      │───▶│   Kubernetes    │
│                 │    │                 │    │     Cluster     │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
  Source of Truth         GitOps Controller       Running Apps
```

## 📁 Project Structure

```
k8s/
├── apps/
│   └── nginx/
│       ├── base/                    # Base Kubernetes manifests
│       │   ├── namespace.yaml
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   ├── configmap.yaml
│       │   └── kustomization.yaml
│       └── overlays/               # Environment-specific overlays
│           ├── development/
│           │   └── kustomization.yaml
│           └── production/
│               └── kustomization.yaml
├── argocd/                         # ArgoCD Applications
│   ├── nginx-development.yaml
│   ├── nginx-production.yaml
│   └── nginx-project.yaml
├── scripts/                        # Utility scripts
│   ├── deploy.sh
│   └── validate.sh
└── README.md
```

## 🚀 Features

### Application Features
- **High Availability**: Production deployment with 5 replicas
- **Resource Management**: Proper CPU and memory limits/requests
- **Health Checks**: Liveness and readiness probes
- **Security**: Non-root containers with dropped capabilities
- **Custom Content**: Environment-specific HTML pages
- **Ingress**: External access configuration

### GitOps Features
- **Multi-Environment**: Separate development and production environments
- **Automated Sync**: Development environment auto-syncs on git changes
- **Manual Approval**: Production requires manual sync for safety
- **Self-Healing**: Automatic drift correction in development
- **Project Management**: Organized with ArgoCD AppProject

### DevOps Features
- **Kustomize**: Environment-specific configuration management
- **Validation**: Pre-deployment manifest validation
- **Monitoring**: Resource usage optimization per environment
- **Security**: RBAC and proper security contexts

## 🛠️ Prerequisites

- Kubernetes cluster (local or remote)
- kubectl configured to access the cluster
- kustomize (for manifest validation)
- Git repository access

### Required Tools (Available in devbox.json)
- `kubectl` - Kubernetes command-line tool
- `kustomize` - Kubernetes configuration management
- `helm` - Package manager for Kubernetes
- `k9s` - Terminal UI for Kubernetes
- `kind` - Local Kubernetes cluster (optional)

## 📋 Quick Start

### 1. Validate Manifests
Before deployment, validate all Kubernetes manifests:

```bash
./scripts/validate.sh
```

### 2. Deploy Everything
Deploy ArgoCD and the nginx application:

```bash
./scripts/deploy.sh
```

### 3. Access ArgoCD UI
Get the admin password and setup port forwarding:

```bash
./scripts/deploy.sh password
./scripts/deploy.sh port-forward
```

Then access ArgoCD at: https://localhost:8080

### 4. Verify Deployment
Check that everything is running:

```bash
./scripts/deploy.sh test
```

## 🔧 Manual Deployment Steps

### Step 1: Install ArgoCD
```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### Step 2: Get ArgoCD Admin Password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 3: Deploy Applications
```bash
# Deploy the AppProject
kubectl apply -f argocd/nginx-project.yaml

# Deploy Applications
kubectl apply -f argocd/nginx-development.yaml
kubectl apply -f argocd/nginx-production.yaml
```

### Step 4: Access ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## 🏃‍♂️ Environment Details

### Development Environment
- **Namespace**: `nginx-app`
- **Replicas**: 1
- **Resources**: Minimal (32Mi memory, 100m CPU)
- **Sync Policy**: Automated with self-healing
- **URL**: http://nginx.local (development content)

### Production Environment
- **Namespace**: `nginx-app`
- **Replicas**: 5
- **Resources**: Enhanced (128Mi memory, 200m CPU)
- **Sync Policy**: Manual approval required
- **URL**: https://nginx.production.local (production content with TLS)

## 📊 Application Components

### Base Components
1. **Namespace**: Isolated environment for the application
2. **Deployment**: nginx container with health checks and security
3. **Service**: ClusterIP service for internal communication
4. **Ingress**: External access with host-based routing
5. **ConfigMap**: Custom HTML content for each environment

### Security Features
- Non-root containers (user 101)
- Dropped capabilities (ALL)
- Read-only root filesystem
- Resource limits and requests
- Network policies (can be added)

## 🔍 Monitoring and Troubleshooting

### Check Application Status
```bash
# ArgoCD applications
kubectl get applications -n argocd

# Nginx pods
kubectl get pods -n nginx-app

# Nginx services
kubectl get svc -n nginx-app

# Nginx ingress
kubectl get ingress -n nginx-app
```

### View Logs
```bash
# Development nginx logs
kubectl logs -l app.kubernetes.io/name=nginx,environment=development -n nginx-app

# Production nginx logs
kubectl logs -l app.kubernetes.io/name=nginx,environment=production -n nginx-app

# ArgoCD application controller logs
kubectl logs -n argocd deployment/argocd-application-controller
```

### Debug Common Issues
```bash
# Check if ArgoCD can access the repository
kubectl describe application nginx-development -n argocd

# Validate kustomize builds locally
kustomize build apps/nginx/overlays/development/
kustomize build apps/nginx/overlays/production/

# Test nginx service connectivity
kubectl run nginx-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://dev-nginx-service.nginx-app.svc.cluster.local
```

## 🔄 GitOps Workflow

### Development Workflow
1. Make changes to `apps/nginx/overlays/development/`
2. Commit and push to git repository
3. ArgoCD automatically syncs changes (within 3 minutes)
4. Verify deployment in ArgoCD UI

### Production Workflow
1. Test changes in development environment
2. Make changes to `apps/nginx/overlays/production/`
3. Commit and push to git repository
4. Manually sync in ArgoCD UI for production
5. Monitor deployment and rollback if needed

## 🎯 Customization

### Adding New Environments
1. Create new overlay in `apps/nginx/overlays/`
2. Customize kustomization.yaml with environment-specific values
3. Create corresponding ArgoCD Application in `argocd/`
4. Update AppProject if needed

### Modifying Resources
- **CPU/Memory**: Update resource requests/limits in overlay patches
- **Replicas**: Modify replica count in overlay patches
- **Image**: Change image version in base deployment or overlay patches
- **Content**: Update ConfigMap data in overlay patches

### Adding Features
- **TLS**: Enable cert-manager annotations in ingress
- **Monitoring**: Add ServiceMonitor for Prometheus
- **Autoscaling**: Add HorizontalPodAutoscaler
- **Network Policies**: Add NetworkPolicy for security

## 🏷️ Tags and Labels

All resources are properly labeled for organization:
- `app.kubernetes.io/name: nginx`
- `app.kubernetes.io/version: "1.25"`
- `app.kubernetes.io/managed-by: argocd`
- `environment: development|production`

## 📚 Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [nginx Docker Hub](https://hub.docker.com/_/nginx)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes in development environment
4. Submit a pull request

## 📜 License

This project is open source and available under the [MIT License](LICENSE).
