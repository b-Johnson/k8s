#!/bin/bash

# Install Istio service mesh
install-istio() {
  echo "📦 Installing Istio..."
  
  # Download and install Istio
  curl -L https://istio.io/downloadIstio | sh -
  cd istio-*
  export PATH=$PWD/bin:$PATH
  
  # Install Istio with demo profile
  istioctl install --set values.defaultRevision=default -y
  
  # Enable sidecar injection for nginx-app namespace
  kubectl label namespace nginx-app istio-injection=enabled --overwrite
  
  echo "✅ Istio installed successfully"
}

# Check Istio installation status
check-istio() {
  echo "🔍 Checking Istio status..."
  
  echo "Istio pods:"
  kubectl get pods -n istio-system
  
  echo -e "\nIstio services:"
  kubectl get svc -n istio-system
  
  echo -e "\nNamespace istio-injection status:"
  kubectl get namespace -L istio-injection
  
  echo -e "\nIstio configuration:"
  kubectl get gateway,virtualservice,destinationrule -n nginx-app
}

# Apply Istio configuration
apply-istio() {
  echo "🚀 Applying Istio configuration..."
  
  kubectl apply -k istio/
  
  echo "✅ Istio configuration applied"
}

# Test traffic distribution
test-traffic() {
  echo "🧪 Testing traffic distribution..."
  
  # Get ingress gateway external IP/port
  export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
  export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
  
  if [[ -z "$INGRESS_HOST" ]]; then
    # For kind cluster, use nodeport
    export INGRESS_HOST="localhost"
    export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
    export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
  fi
  
  echo "Gateway URL: $GATEWAY_URL"
  
  # Test general traffic (should be 80/20 split)
  echo -e "\n🎯 Testing traffic distribution (20 requests):"
  for i in {1..20}; do
    curl -s -H "Host: nginx.local" "http://$GATEWAY_URL/" | grep -o "Version [0-9.]*" || echo "V1"
  done | sort | uniq -c
  
  # Test V2 specific routing
  echo -e "\n🎯 Testing V2 specific routing:"
  curl -s -H "Host: nginx.local" -H "version: v2" "http://$GATEWAY_URL/" | grep -o "Version [0-9.]*"
  
  # Test /v2 prefix routing
  echo -e "\n🎯 Testing /v2 prefix routing:"
  curl -s -H "Host: nginx.local" "http://$GATEWAY_URL/v2/" | grep -o "Version [0-9.]*"
  
  # Test health check distribution
  echo -e "\n🏥 Testing health check distribution (10 requests):"
  for i in {1..10}; do
    curl -s -H "Host: nginx.local" "http://$GATEWAY_URL/health" | grep -o "healthy" && echo " - V1" || echo " - V2"
  done
}

# View traffic analytics
traffic-analytics() {
  echo "📊 Traffic Analytics..."
  
  # Install Prometheus and Grafana addons if not already installed
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/prometheus.yaml
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/grafana.yaml
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/kiali.yaml
  
  echo "Starting port forwards for analytics dashboards..."
  echo "📊 Grafana: http://localhost:3000"
  echo "🕸️  Kiali: http://localhost:20001"
  echo "📈 Prometheus: http://localhost:9090"
  
  # Start port forwards in background
  kubectl -n istio-system port-forward svc/grafana 3000:3000 &
  kubectl -n istio-system port-forward svc/kiali 20001:20001 &
  kubectl -n istio-system port-forward svc/prometheus 9090:9090 &
  
  echo "Press Ctrl+C to stop all port forwards"
  wait
}

# Update traffic weights
update-traffic() {
  local v1_weight=${1:-50}
  local v2_weight=${2:-50}
  
  echo "⚖️  Updating traffic weights: V1=$v1_weight%, V2=$v2_weight%"
  
  # Update the VirtualService
  kubectl patch virtualservice nginx-virtual-service -n nginx-app --type='merge' -p="{
    \"spec\": {
      \"http\": [{
        \"match\": [{\"uri\": {\"exact\": \"/health\"}}],
        \"route\": [{
          \"destination\": {\"host\": \"nginx-service\", \"port\": {\"number\": 80}},
          \"weight\": 50
        }, {
          \"destination\": {\"host\": \"nginx-v2-service\", \"port\": {\"number\": 80}},
          \"weight\": 50
        }]
      }, {
        \"match\": [{\"uri\": {\"prefix\": \"/\"}}],
        \"route\": [{
          \"destination\": {\"host\": \"nginx-service\", \"port\": {\"number\": 80}, \"subset\": \"v1\"},
          \"weight\": $v1_weight
        }, {
          \"destination\": {\"host\": \"nginx-v2-service\", \"port\": {\"number\": 80}, \"subset\": \"v2\"},
          \"weight\": $v2_weight
        }]
      }]
    }
  }"
  
  echo "✅ Traffic weights updated"
}

# Cleanup Istio
cleanup-istio() {
  echo "🧹 Cleaning up Istio..."
  
  # Remove Istio configuration
  kubectl delete -k istio/ || true
  
  # Remove Istio injection label
  kubectl label namespace nginx-app istio-injection- || true
  
  # Uninstall Istio
  istioctl uninstall --purge -y || true
  
  # Remove Istio CRDs
  kubectl delete namespace istio-system || true
  
  echo "✅ Istio cleanup completed"
}

# Main command dispatcher
case "$1" in
  "install")
    install-istio
    ;;
  "check")
    check-istio
    ;;
  "apply")
    apply-istio
    ;;
  "test")
    test-traffic
    ;;
  "analytics")
    traffic-analytics
    ;;
  "update")
    update-traffic "$2" "$3"
    ;;
  "cleanup")
    cleanup-istio
    ;;
  *)
    echo "Istio Service Mesh Management Script"
    echo ""
    echo "Usage: $0 {install|check|apply|test|analytics|update|cleanup}"
    echo ""
    echo "Commands:"
    echo "  install   - Install Istio service mesh"
    echo "  check     - Check Istio installation status"
    echo "  apply     - Apply Istio configuration"
    echo "  test      - Test traffic distribution"
    echo "  analytics - Start analytics dashboards"
    echo "  update    - Update traffic weights (e.g., update 90 10)"
    echo "  cleanup   - Remove Istio installation"
    echo ""
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 test"
    echo "  $0 update 90 10  # 90% V1, 10% V2"
    ;;
esac
