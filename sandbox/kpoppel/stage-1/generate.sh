#!/bin/bash
if [ -f ../config_data ]; then
  echo "Reusing config_data"
  source ../config_data
else
  read -p "Input your domain: " domain
  read -p "Email for use with LetsEncrypt: " acme_email
  read -p "Input user for basic authentication:" user
  read -s -p "Input password for basic authentication:" pass
  read -p "Input filesystem path for persistent volume for Traefik: " data_volume

  echo "domain=$domain" > ../config_data
  echo "acme_email=$acme_email" >> ../config_data
  echo "user=$user" >> ../config_data
  echo "pass=$pass" >> ../config_data
  echo "data_volume=$data_volume" >> ../config_data

  mkdir -p $data_volume
  htpasswd -b -c ../basic_auth_credentials $user $pass
  chmod 600 ../basic_auth_credentials
fi

sed 's#{{DATA_VOLUME}}#'${data_volume}'#g' 03-traefik.persistentvolumeclaim.yaml.j2 > 03-traefik.persistentvolumeclaim.yaml
sed 's/{{ACME_EMAIL}}/'${acme_email}'/g' 04-traefik.deployment.yaml.j2 > 04-traefik.deployment.yaml
sed 's/{{DOMAIN}}/'${domain}'/g' 06-traefik-admin.basic_auth.ingressroute.yaml.j2 > 06-traefik-admin.basic_auth.ingressroute.yaml
sed 's/{{DOMAIN}}/'${domain}'/g' 21-whoami.ingressroute.yaml.j2 > 21-whoami.ingressroute.yaml


read -n1 -p "Press a key to deploy"
kubectl create secret generic system-admin --from-file ../basic_auth_credentials -n kube-system

# Applying all the yaml files at once creates a race condition where CRDs are not stored before being used.
# This is the reason there are two apply runs.
kubectl apply \
    -f 00-klipperlb.daemonset.yaml  \
    -f 01-traefik.crd.yaml
kubectl apply \
    -f 02-traefik.clusterrole.yaml  \
    -f 03-traefik.persistentvolumeclaim.yaml   \
    -f 04-traefik.deployment.yaml   \
    -f 05-basic_auth.admin.middleware.yaml  \
    -f 06-traefik-admin.basic_auth.ingressroute.yaml  \
    -f 10-service.https.middleware.yaml       \
    -f 20-whoami.service.yaml       \
    -f 21-whoami.ingressroute.yaml

echo "Observe deployment. Press <ctrl-c> when all is running and make a few tests."
kubectl get pods -A -w

read -n1 -p "Press a key to make basic tests"
echo "#### Attempt whoami on http:"
curl http://whoami.$domain/notls
echo "#### Attempt whoami on https:"
curl -k https://whoami.$domain/tls
echo "#### Attempt Traefik dashboard using google-chrome browser:"
google-chrome https://traefik.$domain/dashboard/