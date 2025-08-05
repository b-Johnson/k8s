#!/bin/bash

# ArgoCD and Nginx App Deployment Script
# This script sets up ArgoCD and deploys the nginx application

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
    fi

    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl cannot connect to Kubernetes cluster"
    fi

    log "kubectl is available and connected to cluster"
}

# Install ArgoCD
install_argocd() {
    log "Installing ArgoCD..."

    # Create argocd namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    # Install ArgoCD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    # Wait for ArgoCD deployments to be available
    log "Waiting for ArgoCD deployments to be created..."
    sleep 10

    # Wait for ArgoCD to be ready with better error handling
    log "Waiting for ArgoCD server to be ready..."
    if ! kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd; then
        warn "ArgoCD server deployment timeout, checking status..."
        kubectl get deployment argocd-server -n argocd
        kubectl describe deployment argocd-server -n argocd
    fi

    log "Waiting for ArgoCD repo server to be ready..."
    if ! kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd; then
        warn "ArgoCD repo server deployment timeout, checking status..."
        kubectl get deployment argocd-repo-server -n argocd
    fi

    log "Waiting for ArgoCD application controller to be ready..."
    if ! kubectl wait --for=condition=ready --timeout=300s statefulset/argocd-application-controller -n argocd; then
        warn "ArgoCD application controller statefulset timeout, checking status..."
        kubectl get statefulset argocd-application-controller -n argocd
        kubectl describe statefulset argocd-application-controller -n argocd
    fi

    # Verify all components are running
    log "Verifying ArgoCD installation..."
    if kubectl get deployment argocd-server argocd-repo-server -n argocd &>/dev/null && kubectl get statefulset argocd-application-controller -n argocd &>/dev/null; then
        log "ArgoCD installed successfully"
    else
        error "ArgoCD installation verification failed"
    fi
}

# Get ArgoCD admin password
get_argocd_password() {
    log "Retrieving ArgoCD admin password..."
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo
    info "ArgoCD Admin Credentials:"
    info "Username: admin"
    info "Password: $ARGOCD_PASSWORD"
    echo
}

# Setup port forwarding for ArgoCD
setup_port_forward() {
    local port=${1:-8080}
    log "Setting up port forwarding for ArgoCD..."
    info "ArgoCD will be available at: https://localhost:$port"
    info "Press Ctrl+C to stop port forwarding"
    kubectl port-forward svc/argocd-server -n argocd $port:443
}

# Deploy nginx application
deploy_nginx_app() {
    log "Deploying nginx application..."

    # Verify ArgoCD is running before deploying applications
    if ! kubectl get statefulset argocd-application-controller -n argocd &>/dev/null; then
        error "ArgoCD application controller not found. Please install ArgoCD first."
    fi

    # Check if ArgoCD is ready to accept applications
    log "Verifying ArgoCD readiness..."
    if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller --field-selector=status.phase=Running &>/dev/null; then
        warn "ArgoCD application controller pods may not be ready yet"
        kubectl get pods -n argocd
    fi

    # Apply the AppProject first
    log "Creating ArgoCD AppProject..."
    kubectl apply -f "$PROJECT_ROOT/argocd/nginx-project.yaml"

    # Wait a moment for the project to be processed
    sleep 5

    # Apply the Applications
    log "Creating ArgoCD Applications..."
    kubectl apply -f "$PROJECT_ROOT/argocd/nginx-development.yaml"
    kubectl apply -f "$PROJECT_ROOT/argocd/nginx-production.yaml"

    log "Nginx applications deployed to ArgoCD"

    # Wait a bit for applications to sync
    sleep 10

    # Check application status
    info "Checking application status..."
    kubectl get applications -n argocd | grep nginx || warn "No nginx applications found"
}

# Test the deployment
test_deployment() {
    log "Testing nginx deployment..."

    # Wait for nginx pods to be ready
    log "Waiting for nginx pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nginx -n nginx-app --timeout=300s || warn "Some pods may not be ready yet"

    # Get pod status
    info "Nginx pod status:"
    kubectl get pods -n nginx-app -l app.kubernetes.io/name=nginx

    # Get service status
    info "Nginx service status:"
    kubectl get svc -n nginx-app

    # Test nginx service
    info "Testing nginx service..."
    kubectl run nginx-test --image=curlimages/curl --rm -it --restart=Never -- sh -c "
        curl -s http://dev-nginx-service.nginx-app.svc.cluster.local || echo 'Development service not accessible'
        curl -s http://prod-nginx-service.nginx-app.svc.cluster.local || echo 'Production service not accessible'
    " || warn "Service test completed with some failures"
}

# Main function
main() {
    log "Starting ArgoCD and Nginx deployment..."

    case "${1:-all}" in
        "check")
            check_kubectl
            ;;
        "install-argocd")
            check_kubectl
            install_argocd
            get_argocd_password
            ;;
        "deploy-nginx")
            check_kubectl
            deploy_nginx_app
            ;;
        "test")
            check_kubectl
            test_deployment
            ;;
        "port-forward")
            check_kubectl
            setup_port_forward ${2:-8080}
            ;;
        "port-forward-8082")
            check_kubectl
            setup_port_forward 8082
            ;;
        "password")
            get_argocd_password
            ;;
        "all")
            check_kubectl
            install_argocd
            get_argocd_password
            deploy_nginx_app
            test_deployment
            info "Deployment complete! Run '$0 port-forward' to access ArgoCD UI"
            ;;
        *)
            echo "Usage: $0 {check|install-argocd|deploy-nginx|test|port-forward|port-forward-8082|password|all} [port]"
            echo
            echo "Commands:"
            echo "  check              - Check if kubectl is working"
            echo "  install-argocd     - Install ArgoCD in the cluster"
            echo "  deploy-nginx       - Deploy nginx applications to ArgoCD"
            echo "  test               - Test the nginx deployment"
            echo "  port-forward [port] - Setup port forwarding for ArgoCD UI (default: 8080)"
            echo "  port-forward-8082   - Setup port forwarding for ArgoCD UI on port 8082"
            echo "  password           - Get ArgoCD admin password"
            echo "  all                - Run complete deployment (default)"
            exit 1
            ;;
    esac
}

main "$@"
