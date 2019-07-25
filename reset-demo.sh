#!/bin/bash

gcloud compute firewall-rules delete httpbin-allow-80-egressgateway  
kubectl delete -f egress-virtualservice.yaml
kubectl delete -f egress-gateway.yaml
kubectl delete -f egress-destinationrule.yaml
kubectl delete -f egress-serviceentry.yaml -n istio-system