# How to define Ingress definitions for further services

Ingress is the Kubernetes built-in ingress definition.
Traefik gets information from annotations.  Also Helm charts use Ingress definitions, which means
it is possible to use more standard parameters for ingresses.

(Refer to https://docs.traefik.io/migration/v2/)

Use this if TLS is enabled globally:

```
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: example
  namespace: default
spec:
  tls:
  - secretName: myTlsSecret

  rules:
  - host: example.com
    http:
      paths:
      - path: "/foo"
        backend:
          serviceName: example-com
          servicePort: 80
```

Or if just a single Ingress:

```
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: myingress
  namespace: default
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  rules:
  - host: whoami.foo.com
    http:
      paths:
      - path: /
        backend:
          serviceName: whoami
          servicePort: 80
```

# How to define IngressRouter definitions for further services

IngressRouter is a Traefik-specific Custom Resource Definition (CRD)-object.  It can hadle the Traefik specific things directly without using annotations.
Below the commented out lines can be used instead of the ones above them to get a https connection defined.

```
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: ingressroute-notls
#  name: ingressroute-tls
  namespace: default
spec:
  entryPoints:
    - web
#    - websecure
  routes:
    - match: Host(`whoami.{{DOMAIN}}`) && PathPrefix(`/notls`)
#    - match: Host(`whoami.{{DOMAIN}}`) && PathPrefix(`/tls`)
      kind: Rule
      services:
        - name: whoami
          port: 80
#  tls:
#    certResolver: default
```