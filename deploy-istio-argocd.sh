#!/bin/bash

set -e

echo "=========================================="
echo "Deploying Kubernetes with Istio, ArgoCD, and Autoscaler"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl is not installed. Please install kubectl first.${NC}"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Kubernetes cluster is not accessible. Please configure kubectl.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Kubernetes cluster is accessible${NC}"

# Step 1: Create namespace
echo -e "\n${YELLOW}Step 1: Creating microservices namespace...${NC}"
kubectl apply -f k8s-namespace.yaml
echo -e "${GREEN}✓ Namespace created${NC}"

# Step 2: Check if Istio is installed
echo -e "\n${YELLOW}Step 2: Checking Istio installation...${NC}"
if kubectl get namespace istio-system &> /dev/null; then
    echo -e "${GREEN}✓ Istio is installed${NC}"
    # Enable Istio injection for microservices namespace
    kubectl label namespace microservices istio-injection=enabled --overwrite
    echo -e "${GREEN}✓ Istio sidecar injection enabled for microservices namespace${NC}"
else
    echo -e "${RED}✗ Istio is not installed. Please install Istio first.${NC}"
    echo "Run: istioctl install --set values.defaultRevision=default"
    exit 1
fi

# Step 3: Deploy ConfigMaps
echo -e "\n${YELLOW}Step 3: Deploying ConfigMaps...${NC}"
kubectl apply -f k8s-configmap-admin.yaml
kubectl apply -f k8s-configmap-faculty.yaml
kubectl apply -f k8s-configmap-student.yaml
kubectl apply -f k8s-configmap-gateway.yaml
echo -e "${GREEN}✓ ConfigMaps deployed${NC}"

# Step 4: Deploy Services
echo -e "\n${YELLOW}Step 4: Deploying Services...${NC}"
kubectl apply -f k8s-service-admin.yaml
kubectl apply -f k8s-service-faculty.yaml
kubectl apply -f k8s-service-student.yaml
kubectl apply -f k8s-service-gateway.yaml
echo -e "${GREEN}✓ Services deployed${NC}"

# Step 5: Deploy Deployments
echo -e "\n${YELLOW}Step 5: Deploying Microservices...${NC}"
kubectl apply -f k8s-deployment-admin.yaml
kubectl apply -f k8s-deployment-faculty.yaml
kubectl apply -f k8s-deployment-student.yaml
kubectl apply -f k8s-deployment-gateway.yaml
echo -e "${GREEN}✓ Microservices deployed${NC}"

# Step 6: Deploy Autoscaler RBAC
echo -e "\n${YELLOW}Step 6: Deploying Autoscaler RBAC...${NC}"
kubectl apply -f k8s-serviceaccount-autoscaler.yaml
echo -e "${GREEN}✓ Autoscaler RBAC deployed${NC}"

# Step 7: Deploy Autoscaler
echo -e "\n${YELLOW}Step 7: Deploying Autoscaler...${NC}"
kubectl apply -f k8s-deployment-autoscaler.yaml
echo -e "${GREEN}✓ Autoscaler deployed${NC}"

# Step 8: Deploy Istio configurations
echo -e "\n${YELLOW}Step 8: Deploying Istio configurations...${NC}"
kubectl apply -f istio/gateway.yaml
kubectl apply -f istio/virtualservice.yaml
kubectl apply -f istio/destinationrule.yaml
kubectl apply -f istio/peerauthentication.yaml
echo -e "${GREEN}✓ Istio configurations deployed${NC}"

# Step 9: Check if ArgoCD is installed
echo -e "\n${YELLOW}Step 9: Checking ArgoCD installation...${NC}"
if kubectl get namespace argocd &> /dev/null; then
    echo -e "${GREEN}✓ ArgoCD is installed${NC}"
    # Deploy ArgoCD applications
    echo -e "\n${YELLOW}Deploying ArgoCD applications...${NC}"
    echo -e "${YELLOW}⚠ Please update Git repository URLs in argocd/application-*.yaml files before deploying${NC}"
    read -p "Have you updated the Git repository URLs? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl apply -f argocd/namespace.yaml
        kubectl apply -f argocd/application-microservices.yaml
        kubectl apply -f argocd/application-istio.yaml
        echo -e "${GREEN}✓ ArgoCD applications deployed${NC}"
    else
        echo -e "${YELLOW}⚠ Skipping ArgoCD application deployment. Deploy manually after updating repository URLs.${NC}"
    fi
else
    echo -e "${YELLOW}⚠ ArgoCD is not installed. Skipping ArgoCD application deployment.${NC}"
    echo "To install ArgoCD, run:"
    echo "  kubectl create namespace argocd"
    echo "  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
fi

# Step 10: Wait for pods to be ready
echo -e "\n${YELLOW}Step 10: Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=admin-service -n microservices --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=faculty-service -n microservices --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=student-service -n microservices --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=api-gateway -n microservices --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=autoscaler -n microservices --timeout=120s || true

echo -e "\n${GREEN}=========================================="
echo "Deployment Complete!"
echo "==========================================${NC}"

# Display status
echo -e "\n${YELLOW}Current Pod Status:${NC}"
kubectl get pods -n microservices

echo -e "\n${YELLOW}Service Status:${NC}"
kubectl get svc -n microservices

echo -e "\n${YELLOW}Istio Gateway Status:${NC}"
kubectl get gateway -n microservices

echo -e "\n${GREEN}To access services:${NC}"
echo "  kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
echo "  curl http://localhost:8080/api/admin/health"

echo -e "\n${GREEN}To view autoscaler logs:${NC}"
echo "  kubectl logs -f deployment/autoscaler -n microservices"

