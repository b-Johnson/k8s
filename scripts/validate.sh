#!/bin/bash

# Kubernetes Manifest Validation Script
# This script validates the nginx application manifests using kustomize and kubectl

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check required tools
check_tools() {
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v kustomize &> /dev/null; then
        missing_tools+=("kustomize")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    log "All required tools are available"
}

# Validate base manifests
validate_base() {
    log "Validating base manifests..."
    
    cd "$PROJECT_ROOT/apps/nginx/base"
    
    # Build with kustomize
    if kustomize build . > /tmp/nginx-base.yaml; then
        log "Base kustomization build successful"
    else
        error "Base kustomization build failed"
        return 1
    fi
    
    # Validate with kubectl
    if kubectl apply --dry-run=client -f /tmp/nginx-base.yaml > /dev/null; then
        log "Base manifests validation successful"
    else
        error "Base manifests validation failed"
        return 1
    fi
    
    # Show resources that would be created
    info "Base resources:"
    kubectl apply --dry-run=client -f /tmp/nginx-base.yaml | grep -E "^(namespace|deployment|service|ingress|configmap)"
}

# Validate development overlay
validate_development() {
    log "Validating development overlay..."
    
    cd "$PROJECT_ROOT/apps/nginx/overlays/development"
    
    # Build with kustomize
    if kustomize build . > /tmp/nginx-development.yaml; then
        log "Development kustomization build successful"
    else
        error "Development kustomization build failed"
        return 1
    fi
    
    # Validate with kubectl
    if kubectl apply --dry-run=client -f /tmp/nginx-development.yaml > /dev/null; then
        log "Development manifests validation successful"
    else
        error "Development manifests validation failed"
        return 1
    fi
    
    # Show resources that would be created
    info "Development resources:"
    kubectl apply --dry-run=client -f /tmp/nginx-development.yaml | grep -E "^(namespace|deployment|service|ingress|configmap)"
    
    # Check specific development configurations
    info "Development specific configurations:"
    echo "- Replicas: $(yq '.spec.replicas' <<< "$(yq 'select(.kind == "Deployment")' /tmp/nginx-development.yaml)")"
    echo "- Memory Request: $(yq '.spec.template.spec.containers[0].resources.requests.memory' <<< "$(yq 'select(.kind == "Deployment")' /tmp/nginx-development.yaml)")"
}

# Validate production overlay
validate_production() {
    log "Validating production overlay..."
    
    cd "$PROJECT_ROOT/apps/nginx/overlays/production"
    
    # Build with kustomize
    if kustomize build . > /tmp/nginx-production.yaml; then
        log "Production kustomization build successful"
    else
        error "Production kustomization build failed"
        return 1
    fi
    
    # Validate with kubectl
    if kubectl apply --dry-run=client -f /tmp/nginx-production.yaml > /dev/null; then
        log "Production manifests validation successful"
    else
        error "Production manifests validation failed"
        return 1
    fi
    
    # Show resources that would be created
    info "Production resources:"
    kubectl apply --dry-run=client -f /tmp/nginx-production.yaml | grep -E "^(namespace|deployment|service|ingress|configmap)"
    
    # Check specific production configurations
    info "Production specific configurations:"
    echo "- Replicas: $(yq '.spec.replicas' <<< "$(yq 'select(.kind == "Deployment")' /tmp/nginx-production.yaml)")"
    echo "- Memory Request: $(yq '.spec.template.spec.containers[0].resources.requests.memory' <<< "$(yq 'select(.kind == "Deployment")' /tmp/nginx-production.yaml)")"
    echo "- CPU Request: $(yq '.spec.template.spec.containers[0].resources.requests.cpu' <<< "$(yq 'select(.kind == "Deployment")' /tmp/nginx-production.yaml)")"
}

# Validate ArgoCD applications
validate_argocd_apps() {
    log "Validating ArgoCD applications..."
    
    # Validate development application
    if kubectl apply --dry-run=client -f "$PROJECT_ROOT/argocd/nginx-development.yaml" > /dev/null; then
        log "ArgoCD development application validation successful"
    else
        error "ArgoCD development application validation failed"
        return 1
    fi
    
    # Validate production application
    if kubectl apply --dry-run=client -f "$PROJECT_ROOT/argocd/nginx-production.yaml" > /dev/null; then
        log "ArgoCD production application validation successful"
    else
        error "ArgoCD production application validation failed"
        return 1
    fi
    
    # Validate AppProject
    if kubectl apply --dry-run=client -f "$PROJECT_ROOT/argocd/nginx-project.yaml" > /dev/null; then
        log "ArgoCD AppProject validation successful"
    else
        error "ArgoCD AppProject validation failed"
        return 1
    fi
}

# Show manifest differences
show_differences() {
    log "Showing differences between environments..."
    
    if [ -f /tmp/nginx-development.yaml ] && [ -f /tmp/nginx-production.yaml ]; then
        info "Key differences between development and production:"
        echo
        echo "Development deployment name: $(yq 'select(.kind == "Deployment") | .metadata.name' /tmp/nginx-development.yaml)"
        echo "Production deployment name: $(yq 'select(.kind == "Deployment") | .metadata.name' /tmp/nginx-production.yaml)"
        echo
        echo "Development replicas: $(yq 'select(.kind == "Deployment") | .spec.replicas' /tmp/nginx-development.yaml)"
        echo "Production replicas: $(yq 'select(.kind == "Deployment") | .spec.replicas' /tmp/nginx-production.yaml)"
        echo
    fi
}

# Clean up temporary files
cleanup() {
    rm -f /tmp/nginx-*.yaml
    log "Cleanup completed"
}

# Main function
main() {
    log "Starting Kubernetes manifest validation..."
    
    case "${1:-all}" in
        "tools")
            check_tools
            ;;
        "base")
            check_tools
            validate_base
            ;;
        "dev")
            check_tools
            validate_development
            ;;
        "prod")
            check_tools
            validate_production
            ;;
        "argocd")
            check_tools
            validate_argocd_apps
            ;;
        "diff")
            check_tools
            validate_development > /dev/null 2>&1
            validate_production > /dev/null 2>&1
            show_differences
            ;;
        "all")
            check_tools
            validate_base
            validate_development
            validate_production
            validate_argocd_apps
            show_differences
            log "All validations completed successfully!"
            ;;
        *)
            echo "Usage: $0 {tools|base|dev|prod|argocd|diff|all}"
            echo
            echo "Commands:"
            echo "  tools   - Check if required tools are available"
            echo "  base    - Validate base manifests"
            echo "  dev     - Validate development overlay"
            echo "  prod    - Validate production overlay"
            echo "  argocd  - Validate ArgoCD applications"
            echo "  diff    - Show differences between environments"
            echo "  all     - Run all validations (default)"
            exit 1
            ;;
    esac
    
    # Always cleanup at the end
    trap cleanup EXIT
}

main "$@"
