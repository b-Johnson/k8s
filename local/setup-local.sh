#!/bin/bash

# Local development setup with Kind cluster
# This script creates a local Kubernetes cluster and sets up the nginx application

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLUSTER_NAME="nginx-argocd-demo"

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

# Check if kind is available
check_kind() {
    if ! command -v kind &> /dev/null; then
        error "kind is not installed or not in PATH"
    fi
    log "kind is available"
}

# Create kind cluster
create_cluster() {
    log "Creating kind cluster: $CLUSTER_NAME"

    if kind get clusters | grep -q "$CLUSTER_NAME"; then
        warn "Cluster $CLUSTER_NAME already exists"
        return 0
    fi

    kind create cluster --config="$SCRIPT_DIR/kind-config.yaml"

    # Wait for cluster to be ready
    log "Waiting for cluster to be ready..."
    kubectl wait --for=condition=ready nodes --all --timeout=300s

    log "Kind cluster created successfully"
}

# Install ingress controller
install_ingress() {
    log "Installing nginx ingress controller..."

    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

    # Wait for ingress controller to be ready
    log "Waiting for ingress controller to be ready..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s

    log "Nginx ingress controller installed successfully"
}

# Setup local DNS for testing
setup_dns() {
    log "Setting up local DNS entries..."

    # Check if entries already exist
    if grep -q "nginx.local" /etc/hosts 2>/dev/null; then
        warn "DNS entries already exist in /etc/hosts"
        return 0
    fi

    info "Adding DNS entries to /etc/hosts (requires sudo):"
    info "127.0.0.1 nginx.local"
    info "127.0.0.1 nginx.production.local"

    echo "127.0.0.1 nginx.local" | sudo tee -a /etc/hosts
    echo "127.0.0.1 nginx.production.local" | sudo tee -a /etc/hosts

    log "DNS entries added successfully"
}

# Remove DNS entries
cleanup_dns() {
    log "Removing DNS entries from /etc/hosts..."

    sudo sed -i '' '/nginx\.local/d' /etc/hosts 2>/dev/null || true
    sudo sed -i '' '/nginx\.production\.local/d' /etc/hosts 2>/dev/null || true

    log "DNS entries removed"
}

# Delete kind cluster
delete_cluster() {
    log "Deleting kind cluster: $CLUSTER_NAME"

    if ! kind get clusters | grep -q "$CLUSTER_NAME"; then
        warn "Cluster $CLUSTER_NAME does not exist"
        return 0
    fi

    kind delete cluster --name="$CLUSTER_NAME"
    cleanup_dns

    log "Kind cluster deleted successfully"
}

# Get cluster info
cluster_info() {
    log "Kind cluster information:"

    if ! kind get clusters | grep -q "$CLUSTER_NAME"; then
        warn "Cluster $CLUSTER_NAME does not exist"
        return 1
    fi

    echo
    info "Cluster: $CLUSTER_NAME"
    info "Nodes:"
    kubectl get nodes -o wide
    echo
    info "Cluster info:"
    kubectl cluster-info
    echo
    info "Ingress controller status:"
    kubectl get pods -n ingress-nginx
}

# Deploy demo application
deploy_demo() {
    log "Deploying nginx application to local cluster..."

    # First check if kubectl is working
    if ! "$PROJECT_ROOT/scripts/deploy.sh" check; then
        error "kubectl connectivity check failed"
    fi

    # Install ArgoCD first
    log "Installing ArgoCD..."
    if ! "$PROJECT_ROOT/scripts/deploy.sh" install-argocd; then
        error "ArgoCD installation failed"
    fi

    # Wait a bit more for ArgoCD to be fully ready
    log "Waiting for ArgoCD to be fully operational..."
    sleep 30

    # Verify ArgoCD is ready before deploying apps
    if ! kubectl get statefulset argocd-application-controller -n argocd &>/dev/null; then
        error "ArgoCD application controller not found"
    fi

    # Deploy nginx applications
    log "Deploying nginx applications..."
    if ! "$PROJECT_ROOT/scripts/deploy.sh" deploy-nginx; then
        error "Nginx application deployment failed"
    fi

    log "Demo application deployed successfully"

    info "Access points:"
    info "- ArgoCD UI: https://localhost:8080 (run 'task port-forward')"
    info "- Development app: http://nginx.local"
    info "- Production app: http://nginx.production.local"
}

# Test local deployment
test_local() {
    log "Testing local deployment..."

    # Test nginx service accessibility
    log "Testing nginx services..."
    kubectl run nginx-test --image=curlimages/curl --rm -it --restart=Never -- sh -c "
        echo 'Testing development service:'
        curl -s http://dev-nginx-service.nginx-app.svc.cluster.local | grep -o '<title>.*</title>' || echo 'Development service not accessible'
        echo 'Testing production service:'
        curl -s http://prod-nginx-service.nginx-app.svc.cluster.local | grep -o '<title>.*</title>' || echo 'Production service not accessible'
    " || warn "Some services may not be accessible yet"

    # Test ingress (if available)
    log "Testing ingress accessibility..."
    if curl -s http://nginx.local >/dev/null 2>&1; then
        info "Development app accessible at: http://nginx.local"
    else
        warn "Development app not yet accessible via ingress"
    fi

    if curl -s http://nginx.production.local >/dev/null 2>&1; then
        info "Production app accessible at: http://nginx.production.local"
    else
        warn "Production app not yet accessible via ingress"
    fi
}

# Main function
main() {
    case "${1:-help}" in
        "create")
            check_kind
            create_cluster
            install_ingress
            setup_dns
            ;;
        "delete")
            delete_cluster
            ;;
        "info")
            cluster_info
            ;;
        "deploy")
            deploy_demo
            ;;
        "test")
            test_local
            ;;
        "setup-dns")
            setup_dns
            ;;
        "cleanup-dns")
            cleanup_dns
            ;;
        "all")
            check_kind
            create_cluster
            install_ingress
            setup_dns
            deploy_demo
            test_local
            info "Local development environment ready!"
            info "Next steps:"
            info "1. Run 'task port-forward' to access ArgoCD UI"
            info "2. Visit http://nginx.local for development app"
            info "3. Visit http://nginx.production.local for production app"
            ;;
        *)
            echo "Usage: $0 {create|delete|info|deploy|test|setup-dns|cleanup-dns|all}"
            echo
            echo "Commands:"
            echo "  create      - Create kind cluster with ingress"
            echo "  delete      - Delete kind cluster and cleanup"
            echo "  info        - Show cluster information"
            echo "  deploy      - Deploy nginx application"
            echo "  test        - Test local deployment"
            echo "  setup-dns   - Setup local DNS entries"
            echo "  cleanup-dns - Remove local DNS entries"
            echo "  all         - Complete local setup (default)"
            exit 1
            ;;
    esac
}

main "$@"
