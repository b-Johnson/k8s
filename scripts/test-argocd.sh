#!/bin/bash

# ArgoCD Connectivity Test Script
# Tests ArgoCD server connectivity on various ports

set -e

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

# Test ArgoCD connectivity on a specific port
test_argocd_port() {
    local port=${1:-8080}
    local timeout=${2:-5}

    log "Testing ArgoCD connectivity on port $port..."

    # Check if port is listening
    if lsof -i :$port >/dev/null 2>&1; then
        info "✓ Port $port is listening"
    else
        warn "✗ Port $port is not listening"
        return 1
    fi

    # Test HTTP connection
    if curl -k -s --max-time $timeout https://localhost:$port >/dev/null 2>&1; then
        info "✓ HTTP connection successful"
    else
        warn "✗ HTTP connection failed"
        return 1
    fi

    # Test if it's ArgoCD
    if curl -k -s --max-time $timeout https://localhost:$port | grep -qi "argo"; then
        info "✓ ArgoCD detected"
        return 0
    else
        warn "✗ Response doesn't appear to be from ArgoCD"
        return 1
    fi
}

# Test ArgoCD API endpoints
test_argocd_api() {
    local port=${1:-8080}

    log "Testing ArgoCD API endpoints on port $port..."

    # Test health endpoint
    if curl -k -s https://localhost:$port/healthz | grep -q "ok"; then
        info "✓ Health endpoint: OK"
    else
        warn "✗ Health endpoint: Failed"
    fi

    # Test version endpoint
    local version=$(curl -k -s https://localhost:$port/api/version 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$version" ]; then
        info "✓ Version endpoint: $version"
    else
        warn "✗ Version endpoint: Failed"
    fi
}

# Show ArgoCD login information
show_login_info() {
    local port=${1:-8080}

    log "ArgoCD Access Information:"
    echo
    info "URL: https://localhost:$port"
    info "Username: admin"

    # Try to get password
    local password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
    if [ -n "$password" ]; then
        info "Password: $password"
    else
        warn "Could not retrieve password (run 'task password' to get it)"
    fi
    echo
}

# Check if ArgoCD is installed
check_argocd_installed() {
    log "Checking ArgoCD installation..."

    if ! kubectl get namespace argocd >/dev/null 2>&1; then
        error "ArgoCD namespace not found. Install ArgoCD first."
        return 1
    fi

    if ! kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
        error "ArgoCD server deployment not found."
        return 1
    fi

    if ! kubectl get statefulset argocd-application-controller -n argocd >/dev/null 2>&1; then
        error "ArgoCD application controller not found."
        return 1
    fi

    info "✓ ArgoCD is installed"
    return 0
}

# Check ArgoCD pod status
check_argocd_status() {
    log "Checking ArgoCD pod status..."

    local server_ready=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    local controller_ready=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [ "$server_ready" -gt 0 ]; then
        info "✓ ArgoCD server is running ($server_ready pods)"
    else
        warn "✗ ArgoCD server is not running"
    fi

    if [ "$controller_ready" -gt 0 ]; then
        info "✓ ArgoCD application controller is running ($controller_ready pods)"
    else
        warn "✗ ArgoCD application controller is not running"
    fi
}

# Setup port forwarding in background
setup_port_forward_bg() {
    local port=${1:-8080}

    log "Setting up port forwarding to port $port in background..."

    # Kill existing port forwards on this port
    pkill -f "kubectl port-forward.*argocd-server.*$port:443" 2>/dev/null || true

    # Start new port forward
    kubectl port-forward svc/argocd-server -n argocd $port:443 >/dev/null 2>&1 &
    local pf_pid=$!

    # Wait a moment for port forward to establish
    sleep 3

    # Check if port forward is working
    if kill -0 $pf_pid 2>/dev/null && lsof -i :$port >/dev/null 2>&1; then
        info "✓ Port forwarding established (PID: $pf_pid)"
        echo $pf_pid > /tmp/argocd-port-forward-$port.pid
        return 0
    else
        warn "✗ Port forwarding failed"
        return 1
    fi
}

# Stop port forwarding
stop_port_forward() {
    local port=${1:-8080}

    log "Stopping port forwarding on port $port..."

    if [ -f "/tmp/argocd-port-forward-$port.pid" ]; then
        local pid=$(cat /tmp/argocd-port-forward-$port.pid)
        if kill $pid 2>/dev/null; then
            info "✓ Port forwarding stopped (PID: $pid)"
        fi
        rm -f /tmp/argocd-port-forward-$port.pid
    fi

    # Also kill any other port forwards on this port
    pkill -f "kubectl port-forward.*argocd-server.*$port:443" 2>/dev/null || true
}

# Main function
main() {
    local port=${2:-8080}

    case "${1:-test}" in
        "test")
            check_argocd_installed
            check_argocd_status
            test_argocd_port $port
            test_argocd_api $port
            show_login_info $port
            ;;
        "test-8082")
            check_argocd_installed
            check_argocd_status
            test_argocd_port 8082
            test_argocd_api 8082
            show_login_info 8082
            ;;
        "setup")
            check_argocd_installed
            setup_port_forward_bg $port
            sleep 2
            test_argocd_port $port
            show_login_info $port
            ;;
        "setup-8082")
            check_argocd_installed
            setup_port_forward_bg 8082
            sleep 2
            test_argocd_port 8082
            show_login_info 8082
            ;;
        "stop")
            stop_port_forward $port
            ;;
        "stop-8082")
            stop_port_forward 8082
            ;;
        "status")
            check_argocd_installed
            check_argocd_status
            ;;
        "ports")
            log "Checking common ArgoCD ports..."
            for p in 8080 8082 9090; do
                echo
                if lsof -i :$p >/dev/null 2>&1; then
                    test_argocd_port $p
                else
                    warn "Port $p is not listening"
                fi
            done
            ;;
        *)
            echo "Usage: $0 {test|test-8082|setup|setup-8082|stop|stop-8082|status|ports} [port]"
            echo
            echo "Commands:"
            echo "  test [port]    - Test ArgoCD connectivity (default port: 8080)"
            echo "  test-8082      - Test ArgoCD connectivity on port 8082"
            echo "  setup [port]   - Setup port forwarding and test (background)"
            echo "  setup-8082     - Setup port forwarding on 8082 and test"
            echo "  stop [port]    - Stop port forwarding"
            echo "  stop-8082      - Stop port forwarding on 8082"
            echo "  status         - Check ArgoCD installation status"
            echo "  ports          - Check all common ArgoCD ports"
            echo
            echo "Examples:"
            echo "  $0 test 8082                    # Test connection on port 8082"
            echo "  $0 setup-8082                   # Setup port forwarding on 8082"
            echo "  kubectl port-forward svc/argocd-server -n argocd 8082:443 &"
            echo "  $0 test-8082                    # Then test the connection"
            exit 1
            ;;
    esac
}

main "$@"
