Notes for HackMD:

See also: [https://github.com/helm/charts/tree/master/stable/hackmd](https://github.com/helm/charts/tree/master/stable/hackmd)

The helm chart includes everything needed to run the service.  If we want to run only a single instance of Postgresql, the flag

    postgresql.install=false
    postgresql.postgresHost=<host>

must be set.

Disk space must be provisioned as well. It seems this in included, but is unclear for me.  More stuff to learn.