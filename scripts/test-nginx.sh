#!/bin/bash

# Test Nginx Application Script
# Tests nginx deployment functionality

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

# Test nginx pod health
test_nginx_health() {
    log "Testing nginx pod health..."

    local pods=$(kubectl get pods -n nginx-app -l app.kubernetes.io/name=nginx -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [ -z "$pods" ]; then
        warn "No nginx pods found"
        return 1
    fi

    for pod in $pods; do
        local status=$(kubectl get pod $pod -n nginx-app -o jsonpath='{.status.phase}')
        local ready=$(kubectl get pod $pod -n nginx-app -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")

        if [ "$status" = "Running" ] && [ "$ready" = "true" ]; then
            info "✓ $pod: $status (Ready)"

            # Test health endpoint directly in pod
            if kubectl exec $pod -n nginx-app -- curl -s http://localhost:8080/health >/dev/null 2>&1; then
                info "✓ $pod: Health endpoint responsive"
            else
                warn "✗ $pod: Health endpoint not responsive"
            fi
        else
            warn "✗ $pod: $status (Ready: $ready)"

            # Show recent logs for troubleshooting
            info "Recent logs for $pod:"
            kubectl logs $pod -n nginx-app --tail=10 2>/dev/null || echo "No logs available"
        fi
    done
}

# Test service connectivity
test_service_connectivity() {
    log "Testing service connectivity..."

    # Test development service
    if kubectl get svc dev-nginx-service -n nginx-app >/dev/null 2>&1; then
        info "Testing development service..."
        kubectl run nginx-test-dev --image=curlimages/curl --rm -it --restart=Never -- sh -c "
            echo 'Testing health endpoint:'
            curl -s http://dev-nginx-service.nginx-app.svc.cluster.local/health || echo 'Health endpoint failed'
            echo 'Testing main page:'
            curl -s http://dev-nginx-service.nginx-app.svc.cluster.local | head -5 || echo 'Main page failed'
        " 2>/dev/null || warn "Development service test failed"
    fi

    # Test production service
    if kubectl get svc prod-nginx-service -n nginx-app >/dev/null 2>&1; then
        info "Testing production service..."
        kubectl run nginx-test-prod --image=curlimages/curl --rm -it --restart=Never -- sh -c "
            echo 'Testing health endpoint:'
            curl -s http://prod-nginx-service.nginx-app.svc.cluster.local/health || echo 'Health endpoint failed'
            echo 'Testing main page:'
            curl -s http://prod-nginx-service.nginx-app.svc.cluster.local | head -5 || echo 'Main page failed'
        " 2>/dev/null || warn "Production service test failed"
    fi

    # Test simple nginx service (if exists)
    if kubectl get svc nginx-service -n nginx-app >/dev/null 2>&1; then
        info "Testing simple nginx service..."
        kubectl run nginx-test-simple --image=curlimages/curl --rm -it --restart=Never -- sh -c "
            echo 'Testing health endpoint:'
            curl -s http://nginx-service.nginx-app.svc.cluster.local/health || echo 'Health endpoint failed'
            echo 'Testing main page:'
            curl -s http://nginx-service.nginx-app.svc.cluster.local | head -5 || echo 'Main page failed'
        " 2>/dev/null || warn "Simple service test failed"
    fi
}

# Check nginx configuration
check_nginx_config() {
    log "Checking nginx configuration..."

    local pods=$(kubectl get pods -n nginx-app -l app.kubernetes.io/name=nginx -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [ -z "$pods" ]; then
        warn "No nginx pods found"
        return 1
    fi

    local pod=$(echo $pods | awk '{print $1}')

    info "Checking nginx config in pod: $pod"

    # Test nginx config syntax
    if kubectl exec $pod -n nginx-app -- nginx -t >/dev/null 2>&1; then
        info "✓ Nginx configuration is valid"
    else
        warn "✗ Nginx configuration has errors:"
        kubectl exec $pod -n nginx-app -- nginx -t 2>&1 || true
    fi

    # Check if nginx is listening on correct port
    if kubectl exec $pod -n nginx-app -- netstat -tlnp | grep :8080 >/dev/null 2>&1; then
        info "✓ Nginx is listening on port 8080"
    else
        warn "✗ Nginx is not listening on port 8080"
        kubectl exec $pod -n nginx-app -- netstat -tlnp || true
    fi

    # Check cache directories
    if kubectl exec $pod -n nginx-app -- ls -la /var/cache/nginx/ >/dev/null 2>&1; then
        info "✓ Cache directories are accessible"
        kubectl exec $pod -n nginx-app -- ls -la /var/cache/nginx/ | head -5
    else
        warn "✗ Cache directories are not accessible"
    fi
}

# Show nginx status
show_nginx_status() {
    log "Nginx deployment status:"

    echo
    info "Pods:"
    kubectl get pods -n nginx-app -l app.kubernetes.io/name=nginx -o wide 2>/dev/null || echo "No pods found"

    echo
    info "Services:"
    kubectl get svc -n nginx-app 2>/dev/null || echo "No services found"

    echo
    info "Deployments:"
    kubectl get deployment -n nginx-app 2>/dev/null || echo "No deployments found"

    echo
    info "ConfigMaps:"
    kubectl get configmap -n nginx-app 2>/dev/null || echo "No configmaps found"

    echo
    info "Recent events:"
    kubectl get events -n nginx-app --sort-by='.lastTimestamp' | tail -5 2>/dev/null || echo "No events found"
}

# Main function
main() {
    case "${1:-all}" in
        "health")
            test_nginx_health
            ;;
        "service")
            test_service_connectivity
            ;;
        "config")
            check_nginx_config
            ;;
        "status")
            show_nginx_status
            ;;
        "all")
            show_nginx_status
            test_nginx_health
            check_nginx_config
            test_service_connectivity
            log "Nginx testing completed"
            ;;
        *)
            echo "Usage: $0 {health|service|config|status|all}"
            echo
            echo "Commands:"
            echo "  health   - Test nginx pod health and readiness"
            echo "  service  - Test service connectivity"
            echo "  config   - Check nginx configuration"
            echo "  status   - Show nginx deployment status"
            echo "  all      - Run all tests (default)"
            exit 1
            ;;
    esac
}

main "$@"
