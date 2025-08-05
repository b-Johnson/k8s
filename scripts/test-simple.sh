#!/bin/bash

# Simple test script for nginx kubernetes manifests
# Tests basic kubernetes manifests without ArgoCD dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Test basic kubernetes connectivity
test_kubectl() {
    log "Testing kubectl connectivity..."

    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed"
    fi

    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl cannot connect to cluster"
    fi

    log "kubectl connectivity: OK"
}

# Deploy nginx directly without ArgoCD
deploy_nginx_direct() {
    log "Deploying nginx directly to Kubernetes..."

    # Apply base manifests (excluding kustomization.yaml)
    kubectl apply -f "$PROJECT_ROOT/apps/nginx/base/namespace.yaml"
    kubectl apply -f "$PROJECT_ROOT/apps/nginx/base/configmap.yaml"
    kubectl apply -f "$PROJECT_ROOT/apps/nginx/base/deployment.yaml"
    kubectl apply -f "$PROJECT_ROOT/apps/nginx/base/service.yaml"
    kubectl apply -f "$PROJECT_ROOT/apps/nginx/base/ingress.yaml"

    log "Nginx deployed successfully"
}

# Test nginx deployment
test_nginx() {
    log "Testing nginx deployment..."

    # Wait for deployment to be ready
    log "Waiting for nginx deployment to be ready..."
    if kubectl wait --for=condition=available --timeout=300s deployment/nginx-deployment -n nginx-app; then
        log "Nginx deployment is ready"
    else
        warn "Nginx deployment timeout"
        kubectl get deployment nginx-deployment -n nginx-app
        kubectl describe deployment nginx-deployment -n nginx-app
    fi

    # Check pods
    info "Nginx pods:"
    kubectl get pods -n nginx-app

    # Check service
    info "Nginx service:"
    kubectl get svc -n nginx-app

    # Test service connectivity
    log "Testing service connectivity..."
    kubectl run nginx-test --image=curlimages/curl --rm -it --restart=Never -- sh -c "
        curl -s http://nginx-service.nginx-app.svc.cluster.local | grep -o '<title>.*</title>' || echo 'Service not accessible'
    " || warn "Service test failed"
}

# Clean up nginx deployment
cleanup_nginx() {
    log "Cleaning up nginx deployment..."

    kubectl delete -f "$PROJECT_ROOT/apps/nginx/base/ingress.yaml" --ignore-not-found
    kubectl delete -f "$PROJECT_ROOT/apps/nginx/base/service.yaml" --ignore-not-found
    kubectl delete -f "$PROJECT_ROOT/apps/nginx/base/deployment.yaml" --ignore-not-found
    kubectl delete -f "$PROJECT_ROOT/apps/nginx/base/configmap.yaml" --ignore-not-found
    kubectl delete -f "$PROJECT_ROOT/apps/nginx/base/namespace.yaml" --ignore-not-found

    log "Cleanup completed"
}

# Show status of current deployment
show_status() {
    log "Current nginx deployment status:"

    echo
    info "Namespaces:"
    kubectl get namespace nginx-app 2>/dev/null || echo "nginx-app namespace not found"

    echo
    info "Deployments:"
    kubectl get deployment -n nginx-app 2>/dev/null || echo "No deployments found"

    echo
    info "Pods:"
    kubectl get pods -n nginx-app 2>/dev/null || echo "No pods found"

    echo
    info "Services:"
    kubectl get svc -n nginx-app 2>/dev/null || echo "No services found"

    echo
    info "Ingress:"
    kubectl get ingress -n nginx-app 2>/dev/null || echo "No ingress found"
}

# Validate manifests syntax
validate_manifests() {
    log "Validating manifest syntax..."

    # Test each manifest file
    local files=(
        "apps/nginx/base/namespace.yaml"
        "apps/nginx/base/configmap.yaml"
        "apps/nginx/base/deployment.yaml"
        "apps/nginx/base/service.yaml"
        "apps/nginx/base/ingress.yaml"
    )

    for file in "${files[@]}"; do
        if kubectl apply --dry-run=client -f "$PROJECT_ROOT/$file" > /dev/null 2>&1; then
            info "✓ $file"
        else
            error "✗ $file"
        fi
    done

    log "Manifest validation completed"
}

# Main function
main() {
    case "${1:-help}" in
        "test-kubectl")
            test_kubectl
            ;;
        "validate")
            test_kubectl
            validate_manifests
            ;;
        "deploy")
            test_kubectl
            deploy_nginx_direct
            ;;
        "test")
            test_kubectl
            test_nginx
            ;;
        "status")
            show_status
            ;;
        "cleanup")
            cleanup_nginx
            ;;
        "all")
            test_kubectl
            validate_manifests
            deploy_nginx_direct
            test_nginx
            info "Simple nginx deployment completed successfully!"
            info "Next steps:"
            info "1. Check status with: $0 status"
            info "2. Clean up with: $0 cleanup"
            ;;
        *)
            echo "Usage: $0 {test-kubectl|validate|deploy|test|status|cleanup|all}"
            echo
            echo "Commands:"
            echo "  test-kubectl - Test kubectl connectivity"
            echo "  validate     - Validate manifest syntax"
            echo "  deploy       - Deploy nginx directly (no ArgoCD)"
            echo "  test         - Test nginx deployment"
            echo "  status       - Show current deployment status"
            echo "  cleanup      - Remove nginx deployment"
            echo "  all          - Run complete test cycle"
            exit 1
            ;;
    esac
}

main "$@"
