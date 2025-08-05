# Troubleshooting Guide

This guide helps resolve common issues with the Kubernetes nginx application and ArgoCD deployment.

## Common Issues and Solutions

### 1. ArgoCD Installation Issues

#### Error: `deployments.apps "argocd-application-controller" not found`

**Cause**: ArgoCD installation failed or is incomplete.

**Solutions**:
```bash
# Check ArgoCD installation status
kubectl get pods -n argocd

# If pods are pending/failing, check events
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Reinstall ArgoCD
kubectl delete namespace argocd
./scripts/deploy.sh install-argocd

# Use simple test without ArgoCD
task test-simple
```

#### ArgoCD pods stuck in Pending state

**Cause**: Insufficient cluster resources or node issues.

**Solutions**:
```bash
# Check node resources
kubectl describe nodes

# Check for resource constraints
kubectl top nodes
kubectl top pods -n argocd

# For kind clusters, recreate with more resources
./local/setup-local.sh delete
./local/setup-local.sh create
```

### 2. Kubectl Connectivity Issues

#### Error: `kubectl cannot connect to cluster`

**Solutions**:
```bash
# Check current context
kubectl config current-context

# List available contexts
kubectl config get-contexts

# For kind clusters
kind get clusters
kubectl cluster-info --context kind-nginx-argocd-demo

# Test basic connectivity
task test-kubectl
```

### 3. Kind Cluster Issues

#### Cluster creation fails

**Solutions**:
```bash
# Check Docker is running
docker info

# Clean up existing clusters
kind delete cluster --name nginx-argocd-demo

# Recreate cluster
./local/setup-local.sh create

# Check kind logs
kind export logs nginx-argocd-demo
```

#### Port forwarding issues

**Solutions**:
```bash
# Check if ports are in use
lsof -i :8080
lsof -i :80
lsof -i :443

# Kill existing port forwards
pkill -f "kubectl port-forward"

# Alternative ports
kubectl port-forward svc/argocd-server -n argocd 9090:443
```

### 4. Application Deployment Issues

#### ArgoCD applications stuck in "Syncing" state

**Solutions**:
```bash
# Check application status
kubectl describe application nginx-development -n argocd

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller

# Manual sync
kubectl patch application nginx-development -n argocd \
  -p '{"operation":{"sync":{}}}' --type merge
```

#### Applications show "Unknown" health status

**Cause**: Repository not accessible or path incorrect.

**Solutions**:
```bash
# Verify repository URL (update if needed)
kubectl edit application nginx-development -n argocd

# For local testing, use direct deployment
task deploy-simple

# Check if repository is accessible
curl -I https://github.com/b-Johnson/k8s.git
```

### 5. Nginx Application Issues

#### Pods stuck in Pending state

**Solutions**:
```bash
# Check pod details
kubectl describe pod -n nginx-app

# Check node resources
kubectl top nodes

# Check for scheduling issues
kubectl get events -n nginx-app
```

#### Service not accessible

**Solutions**:
```bash
# Test service connectivity
task test-connection

# Check service endpoints
kubectl get endpoints -n nginx-app

# Debug with test pod
kubectl run debug --image=curlimages/curl --rm -it --restart=Never \
  -- curl -v http://nginx-service.nginx-app.svc.cluster.local
```

### 6. Ingress Issues

#### Ingress not working

**Solutions**:
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress resource
kubectl describe ingress -n nginx-app

# Test with port-forward instead
kubectl port-forward svc/nginx-service -n nginx-app 8080:80

# Check DNS entries (for local testing)
cat /etc/hosts | grep nginx
```

## Diagnostic Commands

### Quick Health Check
```bash
# Overall status
task status

# Cluster health
kubectl get nodes
kubectl cluster-info

# ArgoCD health
kubectl get pods -n argocd
kubectl get applications -n argocd

# Nginx health
kubectl get pods -n nginx-app
```

### Detailed Debugging
```bash
# Debug development environment
task debug-dev

# Debug production environment
task debug-prod

# View recent events
kubectl get events --sort-by='.lastTimestamp' -A

# Check resource usage
task top
```

### Log Collection
```bash
# ArgoCD logs
task logs-argocd

# Application logs
task logs-dev
task logs-prod

# System logs (for kind)
kind export logs nginx-argocd-demo
```

## Recovery Procedures

### Complete Reset
```bash
# Clean everything
task clean
task clean-argocd
./local/setup-local.sh delete

# Start fresh
./local/setup-local.sh create
task deploy-all
```

### Partial Reset (Keep ArgoCD)
```bash
# Remove only nginx apps
task clean

# Redeploy nginx
task deploy-nginx
```

### Simple Deployment (No ArgoCD)
```bash
# Test basic functionality
task cleanup-simple
task test-simple
```

## Performance Optimization

### For Development
```bash
# Reduce resources for development
kubectl patch deployment dev-nginx-deployment -n nginx-app \
  -p '{"spec":{"replicas":1}}'

# Scale down ArgoCD (optional)
kubectl scale deployment argocd-repo-server --replicas=1 -n argocd
```

### For Production Testing
```bash
# Increase resources
kubectl patch deployment prod-nginx-deployment -n nginx-app \
  -p '{"spec":{"replicas":3}}'

# Monitor resource usage
watch kubectl top pods -n nginx-app
```

## Getting Help

1. **Check the logs**: Always start with logs and events
2. **Use dry-run**: Test changes with `--dry-run=client`
3. **Validate manifests**: Use `task validate` before deployment
4. **Test incrementally**: Use simple deployment first, then add ArgoCD
5. **Check documentation**: README.md contains detailed setup instructions

## Contact Information

- Repository: https://github.com/b-Johnson/k8s
- Issues: Create an issue in the repository
- Documentation: See README.md for complete setup guide
