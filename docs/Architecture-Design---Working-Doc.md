# Overall Description

PetriPods is a project centered around an opinionated Kubernetes core, providing a core system with all necessary services setup, to make a cluster (single or multi-node) available with SSL/TLS encryption, (??)secured frontend(??), and many services suitable for running a private cluster with interest for home-users.

# Architecture and moving parts

## Definitions
* Server - The physical or virtual machine hosting the K3s Manger & Node.
* Client - The physical or virtual machine from which Ansible is run.
* Ansible - A cross platform, dev-ops automation tool. - Runs on the client and connects to the Server to bootstrap the server.
* Cluster - a collection of one or more managers and nodes working together
* Node - A physical or virtual machine hosting pods
* Pod - a collection of containers that function as a single unit. Often a Pod represents a single Application or service.
* Manager - A Physical or Virtual machine acting as the management interface for your cluster.

## Ansible
Ansible is used to bootstrap a k3s manager & node on the 'server'

## k3s - Kubernetes Implementation
k3s is a 'micro' kubernetes implementation from Rancher Labs.  k3s comes with 'built-in' Traefik 1 and servicelb (a load balancer).
This project omits the installation of Traefik 2 in order to use version 2 of that tool.

## Traefik 2 - a service discovering edge router
Traefik makes it simpler to 'just' deploy services on a cluster.  The services need to be assigned certain values to let Traefik know how it is contacted, and then it will be available a <service>.<domain> afterwards.
Traefik 2 can also ensure SLL certificates are fetched and renewed automatically.  However many are using cert-manager for this purpose.
For this project we will use Traefik to keep things simple

## Redis - a key-value store
Redis is a small key/value store.  It can be used with Traefik 2, for instance to store its configuration.  This will come in handy perhaps, for remote management purposes, as no plaintext file is stored on the cluster, which must then be accessed.
Redis can be used for many other purposes as well, and only a single instance is needed to service other redis consumers.

## Helm Charts - a package manager for Kubernetes
While it can be fun to write Kubernetes objects, it may be easier to use a package system like Helm.
With Helm we can store files on HitHub, and use these directly from there when users deploy services.
With this method deployments will always use the latest available version, and have no need to close the project repository to get up and running.

# UIs
## Rancher - Web UI for managing a Kubernetes cluster

## Kubernetes Dashboard

# Services
The services is the user-facing part of PetriPods.  The project makes available services to deploy on the system via Helm Charts.  If users already have a Kubernetes cluster running, they should in principle be able to pull the charts as well.