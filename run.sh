#!/bin/bash
# Description = This bash script > With using eksctl , creates a simple eks cluster with AWS-LB-CTL and sample Ingress and service .
# HowToUse = " % ./run.sh| tee -a output.md "
# Duration = Around 15 minutes
# https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.5/examples/echo_server/

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### Variables:
export REGION=us-east-1
export CLUSTER_NAME=awslbc
export CLUSTER=$CLUSTER_NAME
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ACC=$AWS_ACCOUNT_ID
export AWS_DEFAULT_REGION=$REGION
# export role_name=AmazonEKS_EFS_CSI_DriverRole_$CLUSTER_NAME


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
 ### 0- Cleanup EFS file system for eks-nfs :
 "
# Do Cleanup


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

iamIdentityMappings:
  - arn: arn:aws:iam::$ACC:user/Ali
    groups:
      - system:masters
    username: admin-Ali
    noDuplicateARNs: true # prevents shadowing of ARNs

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
 ### 3- create iamserviceaccount  : 
 "

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

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
-n kube-system \
--set clusterName=$CLUSTER \
--set serviceAccount.create=false \
--set serviceAccount.name=aws-load-balancer-controller \
--set region=$REGION 


kubectl  -n kube-system logs  -l app.kubernetes.io/name=aws-load-balancer-controller | tee -a  lbc_logs-0.log

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 5- Deploy all the echoserver resources (namespace, service, deployment , ingress) from already checked file  "
# mkdir echoserver 
# cd echoserver 
# wget  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.5/docs/examples/echoservice/echoserver-namespace.yaml 
# wget  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.5/docs/examples/echoservice/echoserver-service.yaml
# wget  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.5/docs/examples/echoservice/echoserver-deployment.yaml
# wget https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.5/docs/examples/echoservice/echoserver-ingress.yaml
# cd ..
#kubectl apply -f echoserver 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
# Namespace :
kubectl apply  -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: echoserver
EOF

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
# Deployment :

kubectl apply  -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echoserver
  namespace: echoserver
spec:
  selector:
    matchLabels:
      app: echoserver
  replicas: 1
  template:
    metadata:
      labels:
        app: echoserver
    spec:
      containers:
      - image: k8s.gcr.io/e2e-test-images/echoserver:2.5
        imagePullPolicy: Always
        name: echoserver
        ports:
        - containerPort: 8080
EOF
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
# Service :
kubectl apply  -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: echoserver
  namespace: echoserver
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector:
    app: echoserver
EOF

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
# Ingress :
kubectl apply  -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echoserver
  namespace: echoserver
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/tags: Environment=dev,Team=test
spec:
  ingressClassName: alb
  rules:
#    - host: echoserver.example.com
    - http:
        paths:
          - path: /
            pathType: Exact
            backend:
              service:
                name: echoserver
                port:
                  number: 80
EOF


kubectl get -n echoserver deploy,svc,ingress

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 6- Checking targetgroupbindings , ingress , controller : "

kubectl -n kube-system logs  -l app.kubernetes.io/name=aws-load-balancer-controller > lbc_logs-1.log
kubectl -n echoserver describe ingress echoserver > ingress-describe.yaml
kubectl -n echoserver describe   targetgroupbindings > targetgroupbindings-describe.yaml 

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###



### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 7- updating ingress with adding Access-Log :"

kubectl apply -f echoserver 

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 7- Recording , , . . . . :"
kubectl   get crd > crd-1.txt


### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 11- For creating Nginx-NLB-SVC run 
     kubectl apply -f  nginx-nlb-svc ; sleep 10 ; kubectl get pod,svc -l app=my-nginx-nlb -o wide

"
