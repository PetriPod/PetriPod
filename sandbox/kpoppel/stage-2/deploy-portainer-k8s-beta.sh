#/!bin/bash
if [ -f ../config_data ]; then
  echo "Reusing config_data"
  source ../config_data
else
  read -p "Input your domain: " domain
  echo "domain=$domain" > ../config_data
  chmod 600 ../config_data
fi
sed 's/{{DOMAIN}}/'${domain}'/g' 11-portainer-k8s-beta.ingressroute.yaml.j2 > 11-portainer-k8s-beta.ingressroute.yaml

echo "About to deploy Portainer-k8s-beta.  Container is available at https://portainer.${domain}/ afterwards."
read -n1 -p "Press a key to continue"


# Values came from this command:
#helm show values portainer/portainer-beta > portainer.helm.values.yaml
# The values file was then changed so tat it uses ClusterIP and the section of ingress was commented out in favour
# of using the portainer-ingressroute yaml file.
kubectl create namespace portainer
helm repo add portainer http://portainer.github.io/portainer-k8s
helm upgrade --atomic -i portainer portainer/portainer-beta --version 1.0.0 -n portainer --values 10-portainer-k8s-beta.helm.values.yaml
kubectl apply -f 11-portainer-k8s-beta.ingressroute.yaml

# Delete portainer pod and Helm chart:
#kubectl delete namespace portainer
#helm delete -n portainer portainer
