# Traefik 2 in k3s with Redis.
**This isn't 100% done, more of a working document. I need to add:**
* Secrets
* Fix k8s dash

**[Go here for more information about IngressRoute](https://docs.traefik.io/routing/providers/kubernetes-crd/)**


Other than that it looks pretty good, although I want to try to store all common config in redis, and not writing `traefik.http.routers.x.tls=true` and `traefik.http.routers.x.tls.certresolver=letsencrypt` for each of our services, much better to do this globally.

This was originally adapted from [this french writeup](https://www.grottedubarbu.fr/traefik-2-k3s/) but now that I know more I have redone most of it. Now much more of it is derived from [the official traefik documentation](https://docs.traefik.io/user-guides/crd-acme/).

Here is the [repository provided by the original author](https://github.com/lfache/K3S-stackfiles). You can also see an example of exposing the kubernetes dashboard here.

## Pre-requisite:
### Install k3s, without traefik:
```
export K3S_KUBECONFIG_MODE="644"
curl -sfL https://get.k3s.io | sh -s - --no-deploy=traefik
```
Check up on your install with:
```
sudo kubectl get pods --all-namespaces
```
Ensure that there is no traefik-* pod running.

### Install kubectl (client PC)
[Install Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

    curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    # Can be skipped if you do not want it in system PATH:
    sudo mv ./kubectl /ust/local/bin

### Allow kubectl from client PC

    scp <user>@<hostip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
    sed -i 's/127\.0\.0\.1/<your>\.<ip>\.<address>\.<here>/g' ~/.kube/config

Test connection

    kubectl get pods --all-namespaces

### Install Helm 3, the package manager (client PC)
[Helm](https://helm.sh/docs/) can be installed through a package manager or just as a binary, like kubectl.  See [Helm Releases](https://github.com/helm/helm/releases).
Here we get the binary, like kubectl.  Perform these steps on the client PC.

    curl https://get.helm.sh/helm-v3.2.4-linux-amd64.tar.gz | tar zxvf -
    # Move to a place on PATH (can be skipped)
    sudo mv linux-amd64/helm /usr/local/bin/helm


### Add stable repo from Helm (client pc)

    helm repo add stable https://kubernetes-charts.storage.googleapis.com/

### Add the Traefik repo

    helm repo add traefik https://containous.github.io/traefik-helm-chart

## Installing Traefik

First we need to update the Helm's repository:
```
helm repo update
```

We can configure flags for traefik by usign `--set foo=bar` in our helm command, or we can use a `values.yaml` file. Here we will speciry our redis configuration (talked more about later down) here. This example specifies a password as plaintext, this **needs to be done using a secret**.

Once we have configured our deployment, we can deploy:
```
helm install \
    --namespace=kube-system \
    --set providers.redis.endpoints=redis.database.svc.cluster.local:6379 \
    --set providers.redis.password=use_a_secret \
    --set persistence.enabled=true \
    traefik \
    traefik/traefik
```

To specify additional configuration for traefik itself, we can use a values.yaml:

    helm show values traefik/traefik >> traefik.values.yaml
    helm install --values=./traefik.values.yaml --namespace=kube-system traefik traefik/traefik

or we can pass arguments directly to the helm CLI:

    helm install --namespace=kube-system --set="additionalArguments={--log.level=DEBUG}" traefik traefik/traefik

Now Traefik has been installed. You should get a 404 by going to any domain or ip that points to your server (on port 80 and 443).

We can test functionality by typing:

```
curl http://10.0.1.5
```
This should return a 404.

### Exposing Services
#### Traefik Dashboard
Now that we have traefik installed, we can start to expose services. Let's start with the traefik dashboard itself. Here is an example:
```
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`traefik.evan.im`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`)
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
```

In this file, we:
* Define a new IngressRoute
* Tell traefik to only route requests to our dashboard if:
    * It is an HTTP request
    * the domain is "traefik.evan.im"
    * the path is /dashboard, or /api
* Tell traefik to route requests that match this criteria to api@internal, or the dashboard.

#### Kubernetes dashboard
Here is an example of routing a service that is not part of traefik itself. For this example we will route HTTPS requests to k3s.evan.im to our kubernetes dashboard. Note here that we are only serving to https requests because of the entrypoint "websecure". Not the port:443 at the bottom. That is telling Traefik what port to find the kubernetes dashboard on locally.

```
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`kdash.example.com`)
      kind: Rule
    services:
      - kind: Service
        name: kubernetes-dashboard
        namespace: kubernetes-dashboard
        passHostHeader: true
        port: 443
```

#### A basic service
Here we will deploy the whoami service with two replicas and route it to ip.evan.im.

```
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

---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: ingressroutetls
  namespace: default
spec:
  entryPoints:
    - web
    - websecure
  routes:
  - match: Host(`your.example.com`) && PathPrefix(`/tls`)
    kind: Rule
    services:
    - name: whoami
      port: 80
```

## Configuration outside of Kubernetes
Up to this point, all of our configuration has been inside of IngressRoute's under Kubernetes. Now we are going to go into things that can not be configured that way, such as acme or anything other than routers. For this, we can either use file or a keystore. I have settled on Redis although this is by no means set in stone.

## Installing Redis
The best helm chart (that I have found so far, message me if you find something better) is from Bitnami. We need to add their repo.

    helm repo add bitnami https://charts.bitnami.com/bitnami

    helm repo update


Now that we have installed the bitnami repo and updated, we are ready to deploy redis. We can do this now with a single helm command:


    helm install redis \
        --set password=use_a_secret \
        --set cluster.enable=false \
        --namespace=database \
        bitnami/redis

Here, we used `--set password=` to set a password. This is something I would not like to carry over from hlos, and with k3s we can use secrets.

First we would create a secret containing the password, and then use `--set existingSecret` to the name of our secret containing our password and `--set existingSecretPasswordKey` to the name of the key containing our password.

## Let's Encrypt!

One of the best parts about traefik is it's ability to issue certificates automatically. Here, we will configure this within redis. To get into a redis "shell", we can execute:

    sudo kubectl exec -n database -it redis-6d54f486f8-65xkj -- redis-cli
    
with `redis-6d54f486f8-65xkj` replaced with your actual redis.

From there we need to set some values. Refer to [traefik documentation on let's encrypt](https://docs.traefik.io/https/acme/) for more information about this. We are going to set some basic settings:

```
set traefik/certificateresolvers/le/acme/email=your.email@example.com
set traefik/certificateresolvers/le/acme/storage=/data/acme.json
set traefik/certificateresolvers/le/acme/httpchallenge/entrypoint=web
set traefik/certificateresolvers/le/acme/storage=/data/acme.json
```

If we would like to enable the traefik dashboard exposed on port 9000, we can just:

    set traefik/ports/traefik/expose=true

**Do not do this unless you are testing. It is unsafe**