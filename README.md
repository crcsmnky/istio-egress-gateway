# Using Istio's Egress Gateway for Outbound Origination

## Setup Infrastructure

### GKE

First, create the GKE cluster:

```bash
gcloud beta container clusters create [CLUSTER_NAME] \
    --machine-type=n1-standard-2 \
    --cluster-version=latest \
    --enable-stackdriver-kubernetes --enable-ip-alias \
    --scopes cloud-platform
```

Grab the cluster credentials - you'll need them for `kubectl` commands to work:

```bash
gcloud container clusters get-credentials [CLUSTER_NAME]
```

Make yourself a `cluster-admin` so you can install Istio:

```bash
kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account)
```

### Istio

Grab the latest release of Istio:

```bash
curl -L https://git.io/getLatestIstio | ISTIO_VERSION=1.2.2 sh -
cd istio-1.2.2
```

Create the `istio-system` namespace:

```bash
kubectl create namespace istio-system
```

Now use `helm` to install the Istio CustomResourceDefinitions:

```bash
helm template install/kubernetes/helm/istio-init \
    --name istio-init \
    --namespace istio-system | kubectl apply -f -
```

Confirm that **23** CRDs we're in fact installed:

```bash
kubectl get crds | grep 'istio.io' | wc -l
```

Now use `helm` to install the Istio control plane components, using the `default` installation profile. Note that we're also installing and configuring the `istio-egressgateway`:

```bash
helm template install/kubernetes/helm/istio \
    --name istio \
    --namespace istio-system \
    --set gateways.istio-egressgateway.enabled=true \
    --set gateways.istio-egressgateway.type=LoadBalancer \
    --set kiali.enabled=true \
    --set grafana.enabled=true | kubectl apply -f -
```

Finally, turn on Istio's auto-injection for the `default` namespace so that all Pods deployed to `default` get the `istio-proxy` automatically injected.

```bash
kubectl label ns default istio-injection=enabled
```

## Deploy Test Apps

We'll use the `sleep` Istio sample to test connectivity:

```bash
kubectl apply -f samples/sleep/sleep.yaml
```

Now create the target system, in this case a Compute Engine VM running [Container-Optimized OS](https://cloud.google.com/container-optimized-os/docs/), which is optimized for running Docker containers:

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

Connect to the instance and deploy `httpbin`:

```bash
gcloud compute ssh httpbin
docker run -p 80:80 -d kennethreitz/httpbin
```

## Configure App to Use Egress Gateway

Deploy the following Istio manifests, which
- Add ServiceEntry for the external `httpbin` service
- Direct in-mesh traffic destined for `httpbin` to the `istio-egressgateway`
- Direct that traffic from `istio-egressgateway` to the `httpbin` VM

```bash
kubectl apply -n istio-system -f egress-serviceentry.yaml
kubectl apply -f egress-destinationrule.yaml
kubectl apply -f egress-gateway.yaml
kubectl apply -f egress-virtualservice.yaml
```

## Test Connectivity and Grab Origin IP

Now send some test traffic to the `httpbin` service:

```bash
APP_POD=$(kubectl get pods -l app=sleep -o jsonpath={.items..metadata.name})
kubectl exec -it $APP_POD -c sleep -- curl -H "Host: httpbin.gcp.external" 1.2.3.4/ip
```

## Configure Firewall

First determine which Node has the `istio-egressgateway` Pod and note it's IP:

```bash
kubectl get pods -l istio=egressgateway -n istio-system -o jsonpath={.items..status.hostIP}
kubectl get nodes -o wide
```

Then create a firewall rule to only allow traffic from that Node's IP:

```bash
gcloud compute firewall-rules create httpbin-allow-80-egressgateway \
--description="Allow traffic on tcp:80 only from istio-egressgateway" \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:80 \
--source-ranges=[SOURCE_NODE_IP_ADDRESS] \
--target-tags=vm-egress-gateway-test
```

Finally confirm that you can still reach the `httpbin` service:

```bash
APP_POD=$(kubectl get pods -l app=sleep -o jsonpath={.items..metadata.name})
kubectl exec -it $APP_POD -c sleep -- curl -H "Host: httpbin.gcp.external" 1.2.3.4/ip
```

## Notes

This sample uses `httpbin.gcp.external` as the hostname of the downstream service. If you examine `egress-serviceentry.yaml` you'll see that the IP of the GCE VM is included there. Due to that configuration, the IP used with `curl` is ignored and only the `Host` header is examined by Istio.