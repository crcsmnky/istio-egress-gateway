# Using Istio's Egress Gateway for Outbound Origination

## Setup GKE and Istio

```bash
gcloud beta container clusters create [CLUSTER_NAME] \
    --machine-type=n1-standard-2 \
    --cluster-version=latest \
    --enable-stackdriver-kubernetes --enable-ip-alias \
    --scopes cloud-platform
```

```bash
gcloud container clusters get-credentials [CLUSTER_NAME]
```

```bash
kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account)
```

```bash
curl -L https://git.io/getLatestIstio | ISTIO_VERSION=1.2.2 sh -
```

```bash
cd istio-1.2.2
kubectl create namespace istio-system
```

```bash
helm template install/kubernetes/helm/istio-init \
    --name istio-init \
    --namespace istio-system | kubectl apply -f -
```

```bash
kubectl get crds | grep 'istio.io' | wc -l
```

```bash
helm template install/kubernetes/helm/istio \
    --name istio \
    --namespace istio-system \
    --set gateways.istio-egressgateway.enabled=true \
    --set gateways.istio-egressgateway.type=LoadBalancer \
    --set kiali.enabled=true \
    --set grafana.enabled=true | kubectl apply -f -
```

## Deploy Test Apps

If not using auto-injection, do this. Otherwise, just deploy without explicit injection

```bash
kubectl apply -f <(istioctl kube-inject -f samples/sleep/sleep.yaml)
```

```bash
gcloud compute instances create httpbin \
    --zone=us-central1-f \
    --machine-type=n1-standard-1 \
    --subnet=default \
    --network-tier=PREMIUM \
    --maintenance-policy=MIGRATE \
    --scopes=cloud-platform \
    --image=cos-stable-75-12105-97-0 \
    --image-project=cos-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard \
    --boot-disk-device-name=httpbin \
    --tags=vm-egress-gateway-test

```

```bash
gcloud compute ssh httpbin --zone us-central1-f
docker run -p 80:80 -d kennethreitz/httpbin
```

## Configure App to Use Egress Gateway

```bash
kubectl apply -f egress-serviceentry.yaml
kubectl apply -f egress-destinationrule.yaml
kubectl apply -f egress-gateway.yaml
kubectl apply -f egress-virtualservice.yaml
```


## Getting external IP address from cluster
```bash
gcloud compute instances list
```

Note, we will need to verify that traffic is indeed coming from the egress gateway 

## Test Connectivity and Grab Origin IP

```bash
APP_POD=$(kubectl get pods -l app=sleep -o jsonpath={.items..metadata.name})
kubectl exec -it $APP_POD -c sleep -- curl -v -H "Host: httpbin.gcp.external" http://192.1.1.1/headers
```

## Configure Firewall

```bash
gcloud compute firewall-rules create httpbin-allow-80-egressgateway \
--description="Allow traffic on tcp:80 only from istio-egressgateway" \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:80 \
--source-ranges=[SOURCE_IP_ADDRESS] \
--target-tags=vm-egress-gateway-test
```
