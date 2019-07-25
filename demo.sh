#!/bin/bash

. $(dirname ${BASH_SOURCE})/util.sh
SOURCE_DIR=$PWD

##############
## NOTE:
## This script assumes there is only one egressgateway instance
## Also assumes the httpbin gcp instances is already created and up and running httpbin
##############


desc "Let's see what pods we have"
run "kubectl get pod"
backtotop

desc "Looking for the istio-egressgateway"
run "kubectl get pod -l istio=egressgateway -n istio-system"
backtotop


tmux split-window -v -d -c $SOURCE_DIR
tmux select-pane -t 0
tmux send-keys -t 1 "gcloud compute ssh httpbin --zone us-central1-f" C-m


# Get the external ip for the egress router
EGRESS_GATEWAY_INTERNAL_HOST_IP=$(kubectl get pod -n istio-system $(k get po -n istio-system | grep egress | awk '{ print $1 }') -o  yaml | grep -i hostip: | cut -d ' ' -f 4)

EGRESS_GATEWAY_EXTERNAL_HOST_IP=$(gcloud compute instances list | grep $EGRESS_GATEWAY_INTERNAL_HOST_IP | awk '{ print $5 }')

read -s
tmux send-keys -t 1 "curl localhost/headers" C-m
read -s 

tmux send-keys -t 1 "exit" C-m
read -s 

HTTPBIN_GCP_IP=$(gcloud compute instances list | grep httpbin | awk '{ print $5 }')
APP_POD=$(kubectl get pods -l app=sleep -o jsonpath={.items..metadata.name})
desc "Let's try execute a command within the sleep pod"
run "kubectl exec -it $APP_POD -c sleep -- curl -v $HTTPBIN_GCP_IP/headers"

desc "Let's add a firewall rule allowing traffic from our istio egress proxy"
run "gcloud compute firewall-rules create httpbin-allow-80-egressgateway --description=\"Allow traffic on tcp:80 only from istio-egressgateway\" --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:80 --source-ranges=$EGRESS_GATEWAY_EXTERNAL_HOST_IP --target-tags=vm-egress-gateway-test"


backtotop

desc "Let's set up the routing rules to route all traffic to our httpbin svc through our egress proxy"

run "kubectl apply -n istio-system -f egress-serviceentry.yaml"
run "kubectl apply -f egress-destinationrule.yaml"
run "kubectl apply -f egress-gateway.yaml"
run "kubectl apply -f egress-virtualservice.yaml"



tmux select-pane -t 1
tmux split-window -h -d -c $SOURCE_DIR
tmux select-pane -t 0
tmux send-keys -t 1 "stern sleep -c istio-proxy" C-m
tmux send-keys -t 2 "stern egress -n istio-system" C-m
backtotop
read -s

desc "Now let's verify we can hit the httpbin svc"
desc "Note, we use hostnames so istio can do the correct routing"
run "kubectl exec -it $APP_POD -c sleep -- curl -v -H \"Host: httpbin.gcp.external\" $HTTPBIN_GCP_IP/headers"



desc "tearing down"
read -s

tmux send-keys -t 1 C-c
tmux send-keys -t 2 C-c

tmux send-keys -t 2 "exit" C-m
tmux send-keys -t 1 "exit" C-m
