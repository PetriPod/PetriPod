#/!bin/bash
if [ -f ../config_data ]; then
  echo "Reusing config_data"
  source ../config_data
else
  read -p "Input your domain: " domain
  echo "domain=$domain" > ../config_data
  chmod 600 ../config_data
fi
sed 's/{{DOMAIN}}/'${domain}'/g' 01-hackmd.ingressroute.yaml.j2 > 01-hackmd.ingressroute.yaml

echo "About to deploy HackMD.  Container is available at https://hackmd.${domain}/ afterwards."
read -n1 -p "Press a key to continue"


# Values came from this command:
#helm show values stable/hackmd > hackmd.helm.values.yaml
# The values file was then changed so that it uses ClusterIP and the section of ingress was commented out in favour
# of using the portainer-ingressroute yaml file.
kubectl create namespace hackmd
helm install hackmd stable/hackmd -n hackmd --values hackmd.helm.values.yaml
kubectl apply -f 01-hackmd.ingressroute.yaml

# Delete portainer pod and Helm chart:
#kubectl delete namespace hackmd
#helm delete -n hackmd hackmd
