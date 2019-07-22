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

```bash
kubectl apply -f samples/sleep/sleep.yaml
```

```bash
gcloud compute --project=sndp-next instances create httpbin \
    --zone=us-central1-f \
    --machine-type=n1-standard-1 \
    --subnet=default \
    --network-tier=PREMIUM \
    --maintenance-policy=MIGRATE \
    --service-account=1059929198189-compute@developer.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --image=cos-stable-75-12105-97-0 \
    --image-project=cos-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard \
    --boot-disk-device-name=httpbin
```

```bash
docker run -p 80:80 -d kennethreitz/httpbin
```

## Configure Firewall

```bash
gcloud compute --project=sndp-next firewall-rules create httpbin-allow-80-egressgateway \
--description="Allow traffic on tcp:80 only from istio-egressgateway" \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:80 \
--source-ranges=10.40.1.9 \
--target-tags=egresstesting
```
