# Hook script for CentOS 6, RHEL 6, and Amazon Linux

This `hook.sh` is includes the dns-01 challenge support along 
with a `deploy_cert` function for restart apache or webmin/usermin 
(if they are installed and running). The restart function is
suitable for CentOS 6, RHEL 6, and Amazon Linux.

The `dehydrated` and `hook.sh` script should not run as root,
however the restart function needs some `service` commands,
the `sudoers-dehydrated' file is suitable for dropping in
`/etc/sudoers.d` assuming the user is called `dehydrated`
