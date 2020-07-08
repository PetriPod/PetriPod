# Notes

This method leaves out the built-in traefik and loadbalancer, and uses metallb and ngins instead.
It follows [this guide](https://medium.com/containerum/how-to-launch-nginx-ingress-and-cert-manager-in-kubernetes-55b182a80c8f) but uses updated versions where available.

# Update Debian

    su -
    apt install curl sudo
    addgroup <user> sudo


# k3s with metallb and nginx as ingress controller

    export K3S_KUBECONFIG_MODE="644"
    export INSTALL_K3S_EXEC=" --no-deploy servicelb --no-deploy traefik"
    curl -sfL https://get.k3s.io | sh -

Check status:

    systemctl status k3s
    kubectl get service --all-namespaces

Look for the --no-deploy and that services are up.

## Install kubectl (client PC)
[Install Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

    curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    # Can be skipped if you do not wat it in system PATH:
    sudo mv ./kubectl /ust/local/bin

## Allow kubectl from client PC

    scp <user>@<hostip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
    sed -i 's/127\.0\.0\.1/<your>\.<ip>\.<address>\.<here>/g' ~/.kube/config

Test connection

    kubectl get pods --all-namespaces

## Install Helm 3, the package manager (client PC)
[Helm](https://helm.sh/docs/) can be installed through a package manager or just as a binary, like kubectl.  See [Helm Releases](https://github.com/helm/helm/releases).
Here we get the binary, like kubectl.  Perform these steps on the client PC.

    curl https://get.helm.sh/helm-v3.2.4-linux-amd64.tar.gz | tar zxvf -
    # Move to a place on PATH (can be skipped)
    sudo mv linux-amd64/helm /usr/local/bin/helm


## Add stable repo from Helm

    helm repo add stable https://kubernetes-charts.storage.googleapis.com/

## Install metallb a bare metal loadbalancer

    helm install metallb stable/metallb --namespace kube-system \
      --set configInline.address-pools[0].name=default \
      --set configInline.address-pools[0].protocol=layer2 \
      --set configInline.address-pools[0].addresses[0]=10.0.0.90-10.0.0.99

The IP range is the one where load balancer listeners will listen.  It is a range on your LAN which you can steer your Internet router towards eventually.

Watch it deploy:

    kubectl get pods -n kube-system -l app=metallb -o wide -w

## Install nginx as ingress controller

    helm install nginx-ingress stable/nginx-ingress --namespace kube-system \
        --set controller.image.repository=quay.io/kubernetes-ingress-controller/nginx-ingress-controller-`dpkg --print-architecture` \
        --set controller.image.tag=0.32.0 \
        --set controller.image.runAsUser=101 \
        --set defaultBackend.enabled=false

Watch it deploy:

    kubectl get pods -n kube-system -l app=nginx-ingress -o wide -w

See which loadbalancer it is connected to:

    kubectl get services  -n kube-system -l app=nginx-ingress -o wide

Test the connection

    curl http://<EXTERNAL-IP>

You should get a 404 not found because no services are connected yet.

## Install cert-manager - option 1
[https://hub.helm.sh/charts/jetstack/cert-manager].  Changes applied as per [description in this issue](https://github.com/jetstack/cert-manager/issues/2752#issuecomment-608357457).

    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    wget https://github.com/jetstack/cert-manager/releases/download/v0.15.1/cert-manager.crds.yaml
    # Edit file according to the description from the issue, save and apply
    # What is done is moving the certificates from a namespace cert-manager to kube-system.  This avoids an error with the
    # added services erroring out on being unable to contact cert-manager-webhook
    kubectl apply --validate=false -f cert-manager.crds.yaml
    helm install cert-manager jetstack/cert-manager --namespace kube-system

Watch it

    kubectl get pods -n kube-system -A -o wide -w

## Install cert-manager - option 2
Further down [the same issue](https://github.com/jetstack/cert-manager/issues/2752#issuecomment-618517062), the devs comment that using a switch when installing using Helm, this problem should be fixed.  It installs the "CRD"s with cert-manager, which means if it gets removed, it will remove all issues certificates as well.  For this project it is like not a real problem.

    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install cert-manager jetstack/cert-manager --namespace kube-system --set installCRDs=true

Watch it

    kubectl get pods -n kube-system -A -o wide -w


## Add LetsEncrypt
LetsEncrypt gives SSL option with certificates issues by LetsEncrypt.

### Use this for staging - test purposes

Add file

```
# letsencrypt.staging.clusterissuer.yaml    
# LetsEncrypt Staging ClusterIssuer
---
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: <EMAIL>
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
---
```

Apply the configuration:

    kubectl apply -f letsencrypt.staging.clusterissuer.yaml

### Use this for production - non-test purposes

Add file

```
# letsencrypt.prod.clusterissuer.yaml
# LetsEncrypt Production ClusterIssuer
---
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: <EMAIL>
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
---
```

Apply the configuration:

    kubectl apply -f letsencrypt.prod.clusterissuer.yaml

# Conclusion on base system setup
At this point we should have metallb, nginx and cert-manager successfully running:

```
$ kubectl get pods -n kube-system -A -o wide -w
NAMESPACE     NAME                                       READY   STATUS    RESTARTS   AGE     IP          NODE     NOMINATED NODE   READINESS GATES
kube-system   local-path-provisioner-6d59f47c7-9f28d     1/1     Running   0          14m     10.42.0.3   debian   <none>           <none>
kube-system   metrics-server-7566d596c8-w599w            1/1     Running   0          14m     10.42.0.4   debian   <none>           <none>
kube-system   coredns-8655855d6-tsf9t                    1/1     Running   0          14m     10.42.0.2   debian   <none>           <none>
kube-system   metallb-speaker-6m6sb                      1/1     Running   0          12m     10.0.0.31   debian   <none>           <none>
kube-system   metallb-controller-6655c976c5-67mtt        1/1     Running   0          12m     10.42.0.5   debian   <none>           <none>
kube-system   nginx-ingress-controller-b9c6bbccb-7hf5x   1/1     Running   0          11m     10.42.0.6   debian   <none>           <none>
kube-system   cert-manager-cainjector-87c85c6ff-bbsn9    1/1     Running   0          8m17s   10.42.0.7   debian   <none>           <none>
kube-system   cert-manager-7747db9d88-bqjwm              1/1     Running   0          8m17s   10.42.0.8   debian   <none>           <none>
kube-system   cert-manager-webhook-55fcfdfd7c-6mw8p      1/1     Running   0          8m17s   10.42.0.9   debian   <none>           <none>
```

Additionally we should see the loadbalancer listening to one of the addresses in the pool assigned to it - in this case 192.168.0.240.  This address is the one to have the internet router forward requests on ports 80 and 443 towards.

The neat thing here is now, that the host IP address is not exposed, and so it is a little safer, as all exposed ports are confied to the services running in the Kubernetes infrastructure.

!NOTE! - Currently untested to set metallb IP pool to be the hostIP - this is how Traefik does it.
```
$ kubectl get service -n kube-system -A -o wide -w
NAMESPACE     NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE   SELECTOR
default       kubernetes                 ClusterIP      10.43.0.1       <none>        443/TCP                      18m   <none>
kube-system   kube-dns                   ClusterIP      10.43.0.10      <none>        53/UDP,53/TCP,9153/TCP       18m   k8s-app=kube-dns
kube-system   metrics-server             ClusterIP      10.43.213.76    <none>        443/TCP                      18m   k8s-app=metrics-server
kube-system   nginx-ingress-controller   LoadBalancer   10.43.139.97    192.168.0.240 80:30996/TCP,443:30671/TCP   15m   app.kubernetes.io/component=controller,app=nginx-ingress,release=nginx-ingress
kube-system   cert-manager               ClusterIP      10.43.161.129   <none>        9402/TCP                     12m   app.kubernetes.io/component=controller,app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=cert-manager
kube-system   cert-manager-webhook       ClusterIP      10.43.232.59    <none>        443/TCP                      12m   app.kubernetes.io/component=webhook,app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=webhook

```

Browsing to http://<yourdomain> should give a 404, and https://<yourdomain> a self-signed certificate warning, then a 404.