# Introduction

This method installs K3S without Traefik 1.x and we deploy Traefik 2 AND KlipperLB on top.
The source of this recipe comes from this [excellent person from Switzerland](https://www.cellerich.ch/2020/02/16/use-traefik-2-x-with-automatic-lets-encrypt-with-your-k3s-cluster-on-civo/).  Reading this article cleared up many hours of frustration for achieving the wanted result: Traefik 2 + Dashboard over https.  What I discovered is the the load balancer is _also_ no installed when Traefik is omitted fromt eh basic installation.

We use two machines: "Server", and "Client".  The headings below signal where the commands are applied from.

The outcome of this first stage is a K3S system with Traefik 2.0, KlipperLB loadbalancer, http and https pulled through, and access to the Traefik dashboard behind BasicAuth.  TLS for LetsEncrypt is also setup, but at the time of writing I was not able to verify as my limit was reached on both staging and production certificates :-)
Traefik 2.2 is out, but it seems to behave a little differently - this needs to be figured out.

Let's go!:

# Server: Update Debian (if you are on Debian)

    su -
    apt install curl sudo
    addgroup <user> sudo

# Server: Install k3s
Follow guide: [K3S Quick Start](https://rancher.com/docs/k3s/latest/en/quick-start/)

    export K3S_KUBECONFIG_MODE="644"
    curl -sfL https://get.k3s.io | sh -s - --no-deploy=traefik

Check status:

    systemctl status k3s
    kubectl get service --all-namespaces
    sudo kubectl get nodes

# Client: Initial setup on client computer
## Install kubectl
[Install Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

    curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    # Can be skipped if you do not wat it in system PATH:
    sudo mv ./kubectl /ust/local/bin

## Setup Bash completion
(From [Kubernetes cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
This will make your life easier!

    source <(kubectl completion bash) # setup autocomplete in bash into the current shell, bash-completion package should be installed first.
    echo "source <(kubectl completion bash)" >> ~/.bashrc # add autocomplete permanently to your bash shell.

## Setup a shorthand alias for kubectl
This will also make your life easier.

    alias kc=kubectl
    complete -F __start_kubectl kc

## Allow kubectl from client PC

    scp <user>@<hostip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
    sed -i 's/127\.0\.0\.1/<your>\.<ip>\.<address>\.<here>/g' ~/.kube/config

Test connection

    kubectl get pods --all-namespaces

## Install Helm 3, the package manager (client PC)
[Helm](https://helm.sh/docs/) can be installed through a package manager or just as a binary, like kubectl.  See [Helm Releases](https://github.com/helm/helm/releases).
Here we get the binary, like kubectl.  Perform these steps on the client PC.  Helm will be used later to install more services.

    curl https://get.helm.sh/helm-v3.2.4-linux-amd64.tar.gz | tar zxvf -
    # Move to a place on PATH (can be skipped)
    sudo mv linux-amd64/helm /usr/local/bin/helm

## Add stable repo from Helm

    helm repo add stable https://kubernetes-charts.storage.googleapis.com/
    helm repo update

# Client: Install Traefik 2 into the cluster
The first thing is to setup cluster roles and role based authorization (RBAC).  The name `"traefik-ingress-controller"` is used, and applied in the namespace `"kube-system"`

## Securing Helm
Skipped for now:
[https://v2.helm.sh/docs/using_helm/#understand-your-security-context]

## Add the Petri Helm Chart Repo
TODO [https://helm.sh/docs/howto/chart_repository_sync_example/]


## KlipperLB - the load balancer which went missing
The load balancer in K3s is not installed if Traefik is taken away.  This will need to be installed again.

```
# File: 00-klipperlb-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: svclb-traefik
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: svclb-traefik
  template:
    metadata:
      labels:
        app: svclb-traefik
        svccontroller.k3s.cattle.io/svcname: traefik
    spec:
      containers:
        - env:
            - name: SRC_PORT
              value: "80"
            - name: DEST_PROTO
              value: TCP
            - name: DEST_PORT
              value: "80"
            - name: DEST_IP
              value: 192.168.211.177
          image: rancher/klipper-lb:v0.1.2
          imagePullPolicy: IfNotPresent
          name: lb-port-80
          ports:
            - containerPort: 80
              hostPort: 80
              name: lb-port-80
              protocol: TCP
          resources: {}
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
        - env:
            - name: SRC_PORT
              value: "443"
            - name: DEST_PROTO
              value: TCP
            - name: DEST_PORT
              value: "443"
            - name: DEST_IP
              value: 192.168.211.177
          image: rancher/klipper-lb:v0.1.2
          imagePullPolicy: IfNotPresent
          name: lb-port-443
          ports:
            - containerPort: 443
              hostPort: 443
              name: lb-port-443
              protocol: TCP
          resources: {}
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
        - env:
            - name: SRC_PORT
              value: "8080"
            - name: DEST_PROTO
              value: TCP
            - name: DEST_PORT
              value: "8080"
            - name: DEST_IP
              value: 192.168.211.177
          image: rancher/klipper-lb:v0.1.2
          imagePullPolicy: IfNotPresent
          name: lb-port-8080
          ports:
            - containerPort: 8080
              hostPort: 8080
              name: lb-port-8080
              protocol: TCP
          resources: {}
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
  updateStrategy:
    rollingUpdate:
      maxUnavailable: 1
    type: RollingUpdate
```

Apply the update on the server:

    kubectl apply -f 00-klipperlb-daemonset.yaml

## Traefik CRD (Custom Resource Definitions)

```
# File: 01-traefik.crd.yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: traefik-ingress-controller

rules:
  - apiGroups:
      - ""
    resources:
      - services
      - endpoints
      - secrets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses/status
    verbs:
      - update
  - apiGroups:
      - traefik.containo.us
    resources:
      - middlewares
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - traefik.containo.us
    resources:
      - ingressroutes
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - traefik.containo.us
    resources:
      - ingressroutetcps
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - traefik.containo.us
    resources:
      - tlsoptions
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - traefik.containo.us
    resources:
      - traefikservices
    verbs:
      - get
      - list
      - watch

---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: traefik-ingress-controller

roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik-ingress-controller
subjects:
  - kind: ServiceAccount
    name: traefik-ingress-controller
    namespace: kube-system
```

Apply the update to the cluster:

    kubectl apply -f 01-traefik.crd.yaml

## Traefik Cluster Role Setup

```
# File: 02-traefik.clusterrole.yaml
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: ingressroutes.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: IngressRoute
    plural: ingressroutes
    singular: ingressroute
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: ingressroutetcps.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: IngressRouteTCP
    plural: ingressroutetcps
    singular: ingressroutetcp
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: middlewares.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: Middleware
    plural: middlewares
    singular: middleware
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: tlsoptions.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: TLSOption
    plural: tlsoptions
    singular: tlsoption
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: traefikservices.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: TraefikService
    plural: traefikservices
    singular: traefikservice
  scope: Namespaced
```

Apply the update to the cluster:

    kubectl apply -f 02-traefik.clusterrole.yaml

## Deploy Traefik on the cluster
Note that this file needs to be updated with your email address for LetsEncrypt to issue certificates based on TLS challenge.

```
# File: 03-traefik.deployment.yaml
apiVersion: v1
kind: Service
metadata:
  name: traefik
  namespace: kube-system
spec:
  #clusterIP: 192.168.211.177
  externalTrafficPolicy: Cluster
  ports:
    - name: web
      nodePort: 32286
      port: 80
      protocol: TCP
      targetPort: web
    - name: websecure
      nodePort: 30108
      port: 443
      protocol: TCP
      targetPort: websecure
    - name: admin
      nodePort: 30582
      port: 8080
      protocol: TCP
      targetPort: admin
  selector:
    app: traefik
  type: LoadBalancer

---
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: kube-system
  name: traefik-ingress-controller

---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: traefik
  namespace: kube-system
  labels:
    app: traefik

spec:
  replicas: 1
  selector:
    matchLabels:
      app: traefik
  template:
    metadata:
      labels:
        app: traefik
    spec:
      serviceAccountName: traefik-ingress-controller
      containers:
        - name: traefik
          # NOTE: Traefik 2.0 installed.  Version 2.2 behaves differently - need to figure that one out.
          image: traefik:v2.0
          args:
            - --api.insecure
            - --accesslog
            - --entrypoints.web.Address=:80
            - --entrypoints.websecure.Address=:443
            - --providers.kubernetescrd
            - --certificatesresolvers.default.acme.tlschallenge
            - --certificatesresolvers.default.acme.email=<YOUR_EMAIL_HERE>
            - --certificatesresolvers.default.acme.storage=acme.json
            # Please note that this is the staging Let's Encrypt server.
            # Once you get things working, you should remove that whole line altogether.
            - --certificatesresolvers.default.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
          ports:
            - name: web
              containerPort: 80
            - name: websecure
              containerPort: 443
            - name: admin
              containerPort: 8080

```

Apply the change on the cluster:

    kubectl apply -f 03-traefik.deployment.yaml

## Setup Middleware to reach the Traefik Dashbord using https and basic authentication
Now we will generate a user and password for basic authentication, and use Kubernetes secrets to store the data.  This way the information is not put in a file somewhere for all to read.

Note that this file needs to be updated with your domain name.  The Traefik dashboard will be available at `https://traefik.<YOUR_DOMAIN_NAME>/` afterwards.

### Create a user and password for basic auth

    # create user:password file 'user'
    htpasswd -c ./user cellerich
    # enter password twice...

### Store the secret in Kubernetes

    kubectl create secret generic traefik-admin --from-file user -n kube-system

### Update the IngressRoute to get access setup

```
# File: 04_traefik-admin.basic_auth.ingressroute.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: traefik-auth
  namespace: kube-system
spec:
  basicAuth:
    secret: traefik-admin

---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: ingressrouteadmin
  namespace: kube-system
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`traefik.<YOUR_DOMAIN_NAME>`)
      kind: Rule
      services:
        - name: traefik
          port: 8080
      middlewares:
        - name: traefik-auth
  tls:
    certResolver: default
```

Apply the update to the cluster:

    kubectl apply -f 04_traefik-admin.basic_auth.ingressroute.yaml

# Client: Test the setup using the whoami service
At this point your K3s cluster is ready to add more services.  To check all is well we will deploy the `whoami` service, which just replies back with some server data when accessed.

```
# File: 00-whoami.service.deployment.yaml
apiVersion: v1
kind: Service
metadata:
  name: whoami

spec:
  ports:
    - protocol: TCP
      name: web
      port: 80
  selector:
    app: whoami

---
kind: Deployment
apiVersion: apps/v1
metadata:
  namespace: default
  name: whoami
  labels:
    app: whoami

spec:
  replicas: 2
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
        - name: whoami
          image: containous/whoami
          ports:
            - name: web
              containerPort: 80
```

Apply the update on the server:

    kubectl apply -f 00-whoami.service.deployment.yaml

## Setup the Ingress Route for the whoami service
This step makes the service visible to the outside through Traefik.

Note that you have to update the file with your domain name.  The whomai service will be available at `http://whoami.<YOUR_DOMAIN_NAME>/notls` and `https://whoami.<YOUR_DOMAIN_NAME>/tls`.


```
# File: 01-whoami.ingressroute.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: ingressroute-notls
  namespace: default
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`whoami.<YOUR_DOMAIN_NAME>`) && PathPrefix(`/notls`)
      kind: Rule
      services:
        - name: whoami
          port: 80

---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: ingressroute-tls
  namespace: default
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`whoami.<YOUR_DOMAIN_NAME>`) && PathPrefix(`/tls`)
      kind: Rule
      services:
        - name: whoami
          port: 80
  tls:
    certResolver: default
```

Apply the update on the server:

    kubectl apply -f 01-whoami.ingressroute.yaml

# Next steps
This to consider to update the above with as next steps:

1. Always forward http to https
1. Make a section for http challenge with LetsEncrypt, if TLS won't work for some reason
1. Update to Traefik 2.2