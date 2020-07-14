
# Adding the first service
Still following [this guide](https://kauri.io/deploy-nextcloud-on-kuberbetes:-the-self-hosted-dropbox/f958350b22794419b09fc34c7284b02e/a) with changes a needed.

The approach here could be templated for other services.

## Update router to point to the loadbalancer

Make your router point to the external IP the nginx-ingress got assigned:

    kubectl get services  -n kube-system -l app=nginx-ingress -o wide

add port 80 and 443 and forward to this address.

## Create service namespace

    kubectl create namespace nextcloud

## Create persistent volume

Make the path exist on the filesystem on the server (important):

    mkdir -p /mnt/ssd/nextcloud

Create file:
```
# nextcloud.persistentvolume.yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: "nextcloud-ssd"
  labels:
    type: "local"
spec:
  storageClassName: "manual"
  capacity:
    storage: "50Gi"
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/ssd/nextcloud"
---
```

Apply configuration and check:

    kubectl apply -f nextcloud.persistentvolume.yaml
    kubectl get pv

Create file:
```
# nextcloud.persistentvolumeclaim.yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  namespace: "nextcloud"
  name: "nextcloud-ssd"
spec:
  storageClassName: "manual"
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: "50Gi"
---
```

Apply configuration and check:

    kubectl apply -f nextcloud.persistentvolumeclaim.yaml
    kubectl get pvc -n nextcloud

## Configure settings for Nextcloud
Get the default config (that is pretty smart!):

    helm show values stable/nextcloud >> nextcloud.values.yaml

Update values in the files for account and data volume:
```
# nextcloud.values.yaml
nextcloud:
  host: "nextcloud.<domain.com>" # Host to reach NextCloud
  username: "admin" # Admin
  password: "<PASSWORD>" # Admin Password
(...)
persistence:
  enabled: true # Change to true
  existingClaim: "nextcloud-ssd" # Persistent Volume Claim created earlier
  accessMode: ReadWriteOnce
  size: "50Gi"
```

## Install Nextcloud

```
helm install nextcloud stable/nextcloud \
  --namespace nextcloud \
  --values nextcloud.values.yaml
```

Check how deployment goes:

    kubectl get pods -n nextcloud
    kubectl get services -n nextcloud -o wide
    kubectl logs -f nextcloud-78f5564f89-854jr -n nextcloud

# Setting the ingress controller
This is where it gets interesting.  The nextcloud.<domain> is now mapped appropriately:

```
# nextcloud.ingress.yaml
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  namespace: "nextcloud" # Same namespace as the deployment
  name: "nextcloud-ingress" # Name of the ingress (see kubectl get ingress -A)
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod" # Encrypt using the ClusterIssuer deployed while setting up Cert-Manager
    nginx.ingress.kubernetes.io/proxy-body-size:  "50m" # Increase the size of the maximum allowed size of the client request body
spec:
  tls:
  - hosts:
    - "nextcloud.<domain.com>" # Host to access nextcloud
    secretName: "nextcloud-prod-tls" # Name of the certifciate (see kubectl get certificate -A) (or use staging)
  rules:
  - host: "nextcloud.<domain.com>" # Host to access nextcloud
    http:
      paths:
        - path: /  # We will access NextCloud via the URL https://nextcloud.<domain.com>/
          backend:
            serviceName: "nextcloud" # Mapping to the service (see kubectl get services -n nextcloud)
            servicePort: 8080 # Mapping to the port (see kubectl get services -n nextcloud)
---
```
Apply the configuration:

    kubectl apply -f nextcloud.ingress.yaml

Let's make a few checks:

    kubectl get certificaterequest -n nextcloud -o wide
    kubectl get certificate -n nextcloud -o wide

Browse to [https://nextcloud.<domain.com>](https://nextcloud.<domain.com>).

The two commands should immediately after show something like this:

```
$ kubectl get certificaterequest -n nextcloud -o wide
NAME                            READY   ISSUER                STATUS                                                                                                     AGE
nextcloud-prod-tls-1343762540   False   letsencrypt-staging   Waiting on certificate issuance from order nextcloud/nextcloud-prod-tls-1343762540-1937212792: "pending"   5s
```

```
$ kubectl get certificate -n nextcloud -o wide
NAME                 READY   SECRET               ISSUER                STATUS                                                                       AGE
nextcloud-prod-tls   False   nextcloud-prod-tls   letsencrypt-staging   Waiting for CertificateRequest "nextcloud-prod-tls-1343762540" to complete   12s
```

To check how the issuer status is, this is one way:

    # Make a note of "cert-manager-*"
    kubectl get pods -n kube-system
    kubectl -n kube-system logs cert-manager-7747db9d88-bqjwm|grep challenge

In the log you will finde something like this:

    http://nextcloud.<DOMAIN>/.well-known/acme-challenge/<verylongstring>\

Visiting that link should give it the secret, showin that LetsEncrypt at least can do the challenge.

# kpoppel notes so far:
I haven't gotten LetsEncrypt to give me a sensible certificate.  The status is always pending

```
$ kubectl get certificaterequest -n nextcloud -o wide
NAME                            READY   ISSUER                STATUS                                                                                                     AGE
nextcloud-prod-tls-1343762540   False   letsencrypt-staging   Waiting on certificate issuance from order nextcloud/nextcloud-prod-tls-1343762540-1937212792: "pending"   93m
```

```
$ kubectl get certificate -n nextcloud -o wide
NAME                 READY   SECRET               ISSUER                STATUS                                                                       AGE
nextcloud-prod-tls   False   nextcloud-prod-tls   letsencrypt-staging   Waiting for CertificateRequest "nextcloud-prod-tls-1343762540" to complete   94m
```

I know what is wrong:

The command `kubectl describe challenges -A` shows what is wrong alongside the log above.  Basically the challenge towarsd LetsEncrypt will not be tried unless a self-check succeeds.  This is all well _provided_ one can hairpin the public IP in one's router.  Many will nt have this option, and so need to have it solved in another way.

Two things to try:
-----------------------
[Applying another setting to nginx, making the loadbalancer think the domain is really external](https://github.com/jetstack/cert-manager/issues/1292#issuecomment-567062724)

```
# nginx.domain.hairpin.yaml
---
kind: Service
apiVersion: v1
metadata:
  name: nginx-ingress-controller
  annotations:
    service.beta.kubernetes.io/do-loadbalancer-hostname: "poulsen.ddns.info"
spec:
#  type: LoadBalancer
#  selector:
#    app: hello
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
---
```
kubectl -n kube-system logs cert-manager-7747db9d88-bqjwm|grep challenge

or making the DNS resolver of the k3s instance use a local DNS resolver - like unbound.
[https://devops.stackexchange.com/questions/6519/kubernetes-on-k3s-cant-resolve-domains-from-custom-dns-server-fritz-box-with-d]

The dns resolver will use the entries in the server /etc/resolv.conf file.

Resources:
[https://rancher.com/docs/rancher/v2.x/en/troubleshooting/dns/](https://rancher.com/docs/rancher/v2.x/en/troubleshooting/dns/)

Enabling DNs logging and follow the log:

```
kubectl get configmap -n kube-system coredns -o json |  kubectl get configmap -n kube-system coredns -o json | sed -e 's_loadbalance_log\\n    loadbalance_g' | kubectl apply -f -
kubectl -n kube-system logs -l k8s-app=kube-dns -f
```

Check that the `/etc/resolv.conf` file is really used:

    kubectl run -i --restart=Never --rm test-${RANDOM} --image=ubuntu --overrides='{"kind":"Pod", "apiVersion":"v1", "spec": {"dnsPolicy":"Default"}}' -- sh -c 'cat /etc/resolv.conf'
Use the k3s DNS resolver

    kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup <something to lookup>