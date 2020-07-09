Notes on the Nextcloud (NC) service:

The login screen will only be served over https as per the Traefik setup.
However NC will redirect to http after login because it cannot see it is being accessed over https.

So an extra config.php file needs to be added like so:

```
  # Extra config files created in /var/www/html/config/
  # ref: https://docs.nextcloud.com/server/15/admin_manual/configuration_server/config_sample_php_parameters.html#multiple-config-php-file
  configs:
    https.config.php |-
      <?php
      $CONFIG = array (
        'overwriteprotocol' => 'https',
      );
```

Checking the file is there is a matter of

    kubectl exec -n nextcloud nextcloud-76db9bcb78-2kstr -i -t -- ls -l config

The file `https.config.php` should be found now.