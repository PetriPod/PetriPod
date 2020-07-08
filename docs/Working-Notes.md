# Deploy k3s via ansible

> requires password-less ssh authentication from the client to the server.
> Also requires passwordless sudo on server.

> Playbook currently installs k3s, and Helm

1. Edit inventory/petridish/hosts.ini
2. Edit inventory/petridish/all.yml - edit the username
2. run `ansible-playbook ansible/site.yml -i ansible/inventory/my-cluster/hosts.ini`


# Quickly up and running (manual way, but to get the process tried)
```
# Install K3S
curl -sfL https://get.k3s.io | sh -

# Install local file storage provider
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl get storageclass

# Get Arkade - a package installer
curl -sLS https://dl.get-arkade.dev | sudo sh

# Install Portainer (Beta) with Kubernetes support
arkade install portainer
```

## Helm Charts
```
# Get Helm
bash <(curl -L https://raw.githubusercontent.com/helm/helm/master/scripts/get)

# Setup service account
kubectl -n kube-system create serviceaccount tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller

# Make sure we don't get a "dial :8080 failure"
kubectl config view --raw > ~/.kube/config

# Initialize
helm init --service-account tiller

# Search for a package
helm search mysql
```

## See running pods (in namespace)
```
kubectl get pods
kubectl -n kube-system get pods
kubectl get service --all-namespaces
```

## Kubernetes dashboard
```
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.3/aio/deploy/recommended.yaml
```
The 'fun' bit here is that it needs a proxy `kubectl proxy`, and this only accepts localhost connections.
kubectl must be installed on the client computer.  The proxy can be run on the K3S node as well, but not attempted.

# Controlling pods from cli
## Get running pods. namespace can be used to see kube-system pods (helm,  traefik, dashboard)
```
kubectl get pods -n <namespace>
```

## Restart a pod
We can restart a pod by effectively scale it to 0 and back up again
```
kubectl scale deployment chat --replicas=0 -n <namespace>
kubectl scale deployment chat --replicas=1 -n <namespace>
```

## Get logs from a pod
```
kubectl -n kube-system logs <traefik-758cd5fc85-6wk99 <- name from get pods command>
```

## Enabling the Traefik Dashboard (it comes disabled)
```
# SSH to server and edit file
nano /var/lib/rancher/k3s/server/manifests/traefik.yaml 

    ...
    metrics:
      prometheus:
        enabled: true
    # These lines:
    dashboard:
     enabled: "true"
     domain: "traefik.<yourdomain>"  (make sure the domain resolves in DNS!)
    # To here ^^^
   kubernetes:
     ...
# Note: The change here is not persisted over master node reboots.  See link below"

# Restart
kubectl apply -f /var/lib/rancher/k3s/server/manifests/traefik.yaml

# Check pod restarted:
kubectl -n kube-system get pods
-> traefik-6cbfb44969-b6rrb                 0/1     Running     0          7s
# Check log for deshboard on port 8080:
kubectl -n kube-system logs traefik-6cbfb44969-b6rrb
-> {"level":"info","msg":"Server configuration reloaded on :8080","time":"2020-06-25T22:01:00Z"}

# Access in browser on http://traefik.<yourdomain> (or https://)
```

## Setup Traefik to use name based routing
Create a file called `traefik.ingress.extensions`:
```
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: petriservices
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: test-all.k3s (your service domain)
    http:
      paths:
      - path: /
        backend:
          serviceName: test-all
          servicePort: http
  - host: tiddlywiki.k3s
    http:
      paths:
      - path: /
        backend:
          serviceName: tiddlywiki
          servicePort: http
```
Then apply the change:
```
kubectl apply -f traefik.ingress.extensions
-> ingress.extensions/petriservices created
# Verify
kubectl get ingress
-> NAME            CLASS    HOSTS                         ADDRESS     PORTS   AGE
-> petriservices   <none>   test-all.k3s,tiddlywiki.k3s   10.0.0.31   80      31s
```

To function 100% some metadata needs to be attached to the pods started as well. Check out the link below on routing.
This is one of the basic operations probably needed for every service deployed as a pod in petri-dish.

## Links used (Thank-you Internet!)
- https://www.portainer.io/2020/04/portainer-for-kubernetes-in-less-than-60-seconds/
- https://stackoverflow.com/questions/45914420/why-tiller-connect-to-localhost-8080-for-kubernetes-api
- https://medium.com/@marcovillarreal_40011/cheap-and-local-kubernetes-playground-with-k3s-helm-5a0e2a110de9
- https://github.com/kubernetes/dashboard
- https://www.replex.io/blog/how-to-install-access-and-add-heapster-metrics-to-the-kubernetes-dashboard
- https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/
- Traefik dashboard: https://forums.rancher.com/t/k3s-traefik-dashboard-activation/17142/9
- Traefik name/path based routing: https://www.alibabacloud.com/blog/how-to-configure-traefik-for-routing-applications-in-kubernetes_594720