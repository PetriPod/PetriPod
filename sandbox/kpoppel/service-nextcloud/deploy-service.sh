#/!bin/bash
# First attempt at generalising the service deployment script

source ../config_data
source ./service.conf

if [ $values_ok != "true" ]; then
  # Getting values for local konfiguration:
  echo "Getting values for '${helmchart}', and storing in '$servicename.helm.values.yaml.j2'"
  helm show values $helmchart > $servicename.helm.values.yaml.j2
  read -n1 -p "Look through the chart, update it and the disable this part of the deployment script."
  echo "Remember that downloading the chart again will **overwrite** the local changes."
  exit 0
fi

sed -e 's/{{DOMAIN}}/'${domain}'/g' \
    -e 's/{{SERVICENAME}}/'${servicename}'/g' \
    -e 's/{{NAMESPACE}}/'${namespace}'/g' \
    -e 's/{{SERVICEPORT}}/'${port}'/g' \
    01-generic.ingressroute.yaml.j2 > 01-$servicename.ingressroute.yaml

sed -e 's/{{DOMAIN}}/'${domain}'/g' \
    -e 's/{{SERVICENAME}}/'${servicename}'/g' \
    -e 's/{{USER}}/'${user}'/g' \
    -e 's/{{PASS}}/'${pass}'/g' \
    $servicename.helm.values.yaml.j2 > $servicename.helm.values.yaml

echo "About to deploy '${servicename}'.  Container is available at https://${servicename}.${domain}/ afterwards."
echo "Watching pods.  Press <ctrl-c> when all pods say Running"
read -n1 -p "Press a key to continue"

# The values file was then changed so that it uses ClusterIP and the section of ingress was commented out in favour
# of using the portainer-ingressroute yaml file.
kubectl create namespace $namespace
helm install $servicename $helmchart -n $namespace --values $servicename.helm.values.yaml
kubectl apply -f 01-$servicename.ingressroute.yaml

echo "If you want to delete the service:"
echo "   kubectl delete namespace $servicename"
echo "If you want to delete the helm chart (you probably do not):"
echo "   helm delete -n hackmd $servicename"

# Watch those pods!
kubectl get pods -n $namespace -o wide -w
