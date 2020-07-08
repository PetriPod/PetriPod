Login to the server and perform this step:

    export K3S_KUBECONFIG_MODE="644"
    curl -sfL https://get.k3s.io | sh -s - --no-deploy=traefik

The on the client machine, get the Kubernetes config file:

    scp <user>@<hostip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
    sed -i 's/127\.0\.0\.1/<your>\.<ip>\.<address>\.<here>/g' ~/.kube/config

See the wiki for bash completig and how to add the kubectl and helm command to the client (or/and server).