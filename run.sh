#!/bin/bash
# Description = This bash script > With using awscli , eksctl , helm , kubectl , and creates a simple eks cluster with AWS-LB-CTL and sample Ingress and service .
# HowToUse = " % ./run.sh| tee -a output.md "
# Duration = Around 15 minutes
# https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.8/examples/echo_server/

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### Variables:
export REGION=ap-southeast-2
export CLUSTER_VER=1.29
export CLUSTER_NAME=awslbc
export CLUSTER=$CLUSTER_NAME
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ACC=$AWS_ACCOUNT_ID
export AWS_DEFAULT_REGION=$REGION



echo " 
### PARAMETERES IN USER >>> 
CLUSTER_NAME=$CLUSTER_NAME  
REGION=$REGION 
AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID

"

if [[ $1 == "cleanup" ]] ;
then 

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 0- Cleanup IRSA  :
 "
# Do Cleanup

kubectl delete -n echoserver ing --all
kubectl delete -n game-2048 ing --all
kubectl delete   ing --all
kubectl delete  svc --all

sleep 30 
kubectl delete -f cluster-autoscaler-autodiscover.yaml
eksctl delete iamserviceaccount --region=$REGION --cluster=$CLUSTER --namespace=kube-system --name=aws-load-balancer-controller 
kubectl  -n kube-system describe sa aws-load-balancer-controller

sleep 30 
eksctl delete cluster $CLUSTER

exit 1
fi;

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 1- Create cluster "

eksctl create cluster  -f - <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER
  region: $REGION
  version: "$CLUSTER_VER"

managedNodeGroups:
  - name: mng
    privateNetworking: true
    desiredCapacity: 2
    instanceType: t3.medium
    labels:
      worker: linux
    maxSize: 3
    minSize: 0
    volumeSize: 20
    ssh:
      allow: true
      publicKeyPath: AliSyd

kubernetesNetworkConfig:
  ipFamily: IPv4 # or IPv6

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
#  - name: aws-ebs-csi-driver

iam:
  withOIDC: true

#iamIdentityMappings:
#  - arn: arn:aws:iam::$ACC:user/Ali
#    groups:
#      - system:masters
#    username: admin-Ali
#    noDuplicateARNs: true # prevents shadowing of ARNs

cloudWatch:
  clusterLogging:
    enableTypes:
      - "*"

EOF

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 2- kubeconfig  : "
aws eks update-kubeconfig --name $CLUSTER --region $REGION

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### 3- Check cluster node and infrastructure pods  : "
kubectl get node
kubectl -n kube-system get pod 
kubectl   get crd > crd-0.txt

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 3- Create IRSA  : 
 "
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.2/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json

eksctl create iamserviceaccount \
--region=$REGION \
--cluster=$CLUSTER \
--namespace=kube-system \
--name=aws-load-balancer-controller \
--attach-policy-arn=arn:aws:iam::$ACC:policy/AWSLoadBalancerControllerIAMPolicy \
--override-existing-serviceaccounts \
--approve

kubectl  -n kube-system describe sa aws-load-balancer-controller > aws-load-balancer-controller_sa.yaml 


### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 4 - Install lbc with helm  : 
 "
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
-n kube-system \
--set clusterName=$CLUSTER \
--set serviceAccount.create=false \
--set serviceAccount.name=aws-load-balancer-controller \
--set region=$REGION 


kubectl  -n kube-system logs  -l app.kubernetes.io/name=aws-load-balancer-controller 

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 5- Deploy all the echoserver resources (namespace, service, deployment , ingress) from already checked file  "

kubectl apply -f echoserver



### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 6- Deploy all the echoserver resources (namespace, service, deployment , ingress) from already checked file  "


kubectl apply -f game2048



### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 7- Deploy all the echoserver resources (namespace, service, deployment , ingress) from already checked file  "


kubectl apply -f nginxweb



### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 8- Deploy all the echoserver resources (namespace, service, deployment , ingress) from already checked file  "

kubectl apply -f nginx-nlb-svc

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 9 - Recording configs and status  "


STAT=`date +%s`
mkdir $STAT
sleep 30
cp iam-policy.json $STAT
kubectl -n kube-system logs  -l app.kubernetes.io/name=aws-load-balancer-controller > $STAT/lbc_logs-1.log
kubectl -n kube-system get pod  -l app.kubernetes.io/name=aws-load-balancer-controller -o yaml > $STAT/lbc_pod.log
kubectl  -n kube-system describe sa  aws-load-balancer-controller  > $STAT/aws-load-balancer-controller.yaml
kubectl get ingress -A -o wide > $STAT/ings.txt
kubectl get svc -A -o wide > $STAT/svcs.txt
kubectl describe targetgroupbindings -A > $STAT/tgBindings.yaml 
kubectl   get crd > $STAT/crd.txt

mkdir $STAT/echoserver
kubectl  -n echoserver describe ingress echoserver > $STAT/echoserver/ingress.yaml
kubectl  -n echoserver describe svc > $STAT/echoserver/vc.yaml
kubectl  -n echoserver describe ep > $STAT/echoserver/ep.yaml
kubectl  -n echoserver describe pod > $STAT/echoserver/pod.yaml
kubectl  -n echoserver describe targetgroupbindings > $STAT/echoserver/tgBinding.yaml 

mkdir $STAT/game-2048
kubectl  -n game-2048 describe ingress echoserver > $STAT/game-2048/ingress.yaml
kubectl  -n game-2048 describe svc > $STAT/game-2048/svc.yaml
kubectl  -n game-2048 describe ep > $STAT/game-2048/ep.yaml
kubectl  -n game-2048 describe ep > $STAT/game-2048/pod.yaml
kubectl  -n game-2048 describe targetgroupbindings > $STAT/game-2048/tgBinding.yaml 

$STAT/default
kubectl   describe ingress echoserver > $STAT/default/nginxweb_ingress.yaml
kubectl   describe svc > $STAT/default/svc.yaml
kubectl   describe pod > $STAT/default/pod.yaml
kubectl   describe ep > $STAT/default/ep.yaml
kubectl   describe targetgroupbindings > $STAT/default/tgBinding.yaml 


