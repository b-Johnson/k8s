#!/bin/bash

# ArgoCD Diagnostic Script
# This script helps diagnose ArgoCD installation and deployment issues

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check cluster connectivity
check_cluster() {
    log "Checking cluster connectivity..."

    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed"
        return 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    info "✓ kubectl connectivity OK"
    kubectl cluster-info
}

# Check ArgoCD namespace
check_namespace() {
    log "Checking ArgoCD namespace..."

    if kubectl get namespace argocd &>/dev/null; then
        info "✓ ArgoCD namespace exists"
    else
        warn "✗ ArgoCD namespace not found"
        return 1
    fi
}

# Check ArgoCD resources
check_argocd_resources() {
    log "Checking ArgoCD resources..."

    echo
    info "=== ArgoCD Deployments ==="
    kubectl get deployments -n argocd 2>/dev/null || warn "No deployments found"

    echo
    info "=== ArgoCD StatefulSets ==="
    kubectl get statefulsets -n argocd 2>/dev/null || warn "No statefulsets found"

    echo
    info "=== ArgoCD Services ==="
    kubectl get services -n argocd 2>/dev/null || warn "No services found"

    echo
    info "=== ArgoCD Pods ==="
    kubectl get pods -n argocd 2>/dev/null || warn "No pods found"
}

# Check ArgoCD pod status
check_pod_status() {
    log "Checking ArgoCD pod status..."

    local pods=$(kubectl get pods -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [ -z "$pods" ]; then
        warn "No ArgoCD pods found"
        return 1
    fi

    for pod in $pods; do
        local status=$(kubectl get pod $pod -n argocd -o jsonpath='{.status.phase}')
        local ready=$(kubectl get pod $pod -n argocd -o jsonpath='{.status.containerStatuses[0].ready}')

        if [ "$status" = "Running" ] && [ "$ready" = "true" ]; then
            info "✓ $pod: $status (Ready)"
        else
            warn "✗ $pod: $status (Ready: $ready)"
            kubectl describe pod $pod -n argocd | tail -10
        fi
    done
}

# Check ArgoCD logs
check_logs() {
    log "Checking ArgoCD logs (last 20 lines)..."

    echo
    info "=== ArgoCD Server Logs ==="
    kubectl logs -n argocd deployment/argocd-server --tail=20 2>/dev/null || warn "Cannot get server logs"

    echo
    info "=== ArgoCD Repo Server Logs ==="
    kubectl logs -n argocd deployment/argocd-repo-server --tail=20 2>/dev/null || warn "Cannot get repo server logs"

    echo
    info "=== ArgoCD Application Controller Logs ==="
    kubectl logs -n argocd statefulset/argocd-application-controller --tail=20 2>/dev/null || warn "Cannot get application controller logs"
}

# Check cluster resources
check_cluster_resources() {
    log "Checking cluster resources..."

    echo
    info "=== Node Status ==="
    kubectl get nodes -o wide

    echo
    info "=== Node Resources ==="
    kubectl top nodes 2>/dev/null || warn "Metrics server not available"

    echo
    info "=== ArgoCD Namespace Events ==="
    kubectl get events -n argocd --sort-by='.lastTimestamp' | tail -10 2>/dev/null || warn "No events found"
}

# Try to fix common issues
fix_common_issues() {
    log "Attempting to fix common ArgoCD issues..."

    # Recreate namespace
    log "Recreating ArgoCD namespace..."
    kubectl delete namespace argocd --ignore-not-found --timeout=60s
    kubectl create namespace argocd

    # Reinstall ArgoCD
    log "Reinstalling ArgoCD..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    # Wait for installation
    log "Waiting for ArgoCD installation..."
    sleep 30

    # Check status
    check_argocd_resources
}

# Test ArgoCD access
test_argocd_access() {
    log "Testing ArgoCD access..."

    # Check if server is ready
    if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
        warn "ArgoCD server deployment not found"
        return 1
    fi

    # Test port forward
    log "Testing ArgoCD server port-forward..."
    kubectl port-forward svc/argocd-server -n argocd 8080:443 &
    local pf_pid=$!

    sleep 5

    if curl -k -s https://localhost:8080 | grep -q "Argo CD"; then
        info "✓ ArgoCD server accessible via port-forward"
    else
        warn "✗ ArgoCD server not accessible"
    fi

    kill $pf_pid 2>/dev/null || true
}

# Main function
main() {
    case "${1:-all}" in
        "cluster")
            check_cluster
            ;;
        "namespace")
            check_namespace
            ;;
        "resources")
            check_argocd_resources
            ;;
        "pods")
            check_pod_status
            ;;
        "logs")
            check_logs
            ;;
        "cluster-resources")
            check_cluster_resources
            ;;
        "fix")
            fix_common_issues
            ;;
        "test-access")
            test_argocd_access
            ;;
        "all")
            check_cluster
            check_namespace
            check_argocd_resources
            check_pod_status
            check_cluster_resources
            log "ArgoCD diagnostic completed"
            ;;
        *)
            echo "Usage: $0 {cluster|namespace|resources|pods|logs|cluster-resources|fix|test-access|all}"
            echo
            echo "Commands:"
            echo "  cluster          - Check cluster connectivity"
            echo "  namespace        - Check ArgoCD namespace"
            echo "  resources        - Check ArgoCD resources"
            echo "  pods             - Check pod status"
            echo "  logs             - Show ArgoCD logs"
            echo "  cluster-resources - Check cluster resources"
            echo "  fix              - Try to fix common issues"
            echo "  test-access      - Test ArgoCD server access"
            echo "  all              - Run all diagnostics (default)"
            exit 1
            ;;
    esac
}

main "$@"
