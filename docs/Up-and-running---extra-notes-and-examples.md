# Examples

## Example configuration of Ingress with SSL

    ---
    apiVersion: extensions/v1beta1
    kind: Ingress
    metadata:
      name: my-ingress
      annotations:
        kubernetes.io/ingress.class: "nginx"
        cert-manager.io/cluster-issuer: "letsencrypt-staging"
    spec:
      tls:
      - hosts:
        - <domain>
        secretName: "<domain>-staging-tls"
      rules:
      - host: <domain>
        http:
          paths:
            - path: /
              backend:
                serviceName: <service_name>
                servicePort: 80
    ---

## Example persistent volume configuration

First add a definition of the volume, path and size. Add file example.nfs.persistentvolume.yaml:

    # example.nfs.persistentvolume.yaml
    ---
    apiVersion: v1
    kind: PersistentVolume
    metadata:
      name: example-ssd-volume
      labels:
        type: local
    spec:
      storageClassName: manual
      capacity:
        storage: 1Gi
      accessModes:
        - ReadWriteOnce
      hostPath:
        path: "/mnt/ssd/example"
    ---

Apply the configuration:

    kubectl apply -f example.nfs.persistentvolume.yaml

To apply the claim for a volume do like this. Add file example.bfs.persistentvolumechaim.yaml

    # example.nfs.persistentvolumeclaim.yml
    ---
      apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: example-ssd-volume
      spec:
        storageClassName: manual
        accessModes:
          - ReadWriteOnce
        resources:
      requests:
            storage: 1Gi
    ---

    kubectl apply -f example.nfs.persistentvolumeclaim.yaml

[Kubernetes PersistentVolumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/}

# Other useful information

## Useful commands

    kubectl -n <service> logs -f $(kubectl -n <service> get pod -o name)
    kubectl -n <service> decribe $(kubectl -n <service> get pod -o name)


## Helm Commands
[https://helm.sh/docs/intro/quickstart/#initialize-a-helm-chart-repository]

Search the repo

        helm search repo stable

Update the repo

        helm repo update

Install a pod

        helm install stable/hackmd --generate-name

Get information

        helm show chart stable/hackmd

or

        helm show all stable/hackmd

Removing a pod

        helm uninstall hackmd

## Watching deployment status
It takes a while to deploy a container, just like docker pull.  Watch the progress like this

        kubectl get pods -w

When it says "Running" you are good to go.

## Initial contact
Follow the instauction emitted by Helm.  This will not create a link to Traefik, just a temporary port forward to the new service.

        kubectl port-forward hackmd-1593264092-7984f4cfd6-4q9r6 8080:3000

Note the help text for this particular Helm Chart is wrong on the listening port of that container.
This was found by issuing a `kubectl logs <pod nmae>` and looking at the logfile.

## Securing Helm
Skipped for now:
[https://v2.helm.sh/docs/using_helm/#understand-your-security-context]

# Add the Petri Helm Chart Repo
TODO [https://helm.sh/docs/howto/chart_repository_sync_example/]


# Links
LetsEncrypt Clusterissuer and more:
https://medium.com/containerum/how-to-launch-nginx-ingress-and-cert-manager-in-kubernetes-55b182a80c8f