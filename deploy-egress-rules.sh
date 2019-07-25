#!/bin/bash
kubectl apply -f egress-serviceentry.yaml -n istio-system
kubectl apply -f egress-destinationrule.yaml
kubectl apply -f egress-gateway.yaml
kubectl apply -f egress-virtualservice.yaml