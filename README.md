# Dehydrated Route 53 Hook Script
Dehydrated hook script that employs cli53 to enable dns-01 challenges with AWS Route 53 DNS hosting

The `hook.sh` can me used in conjuntion with [`dehydrated`](https://github.com/lukas2511/dehydrated) and Let's Encrypt's service (letsencrypt.org) to issue SSL certificates for domain names hosted in [AWS Route 53](https://aws.amazon.com/route53/). The script is based on dehydrated `hook.sh` template, and heavily leverages the excellent [`cli53` Route 53 client](https://github.com/barnybug/cli53). It is designed to be called by the `dehydrated` script to create and delete dns-01 challenge records.

The script will automatically identify the correct Route 53 zone for each domain name. It also supports certificates with alternative domain names in different Route 53 zones

The script requires:
- [cli53](https://github.com/barnybug/cli53)
- bash
- jq
- sed
- xargs
- mailx (just for emailing errors)

For `cli53` to work, it requires AWS credentials with access to Route 53, with permissions
to list zones, and to create and delete records in zones. Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables, or create `~/.aws/credentials` file with `[default]` credentials, or set `AWS_PROFILE` to name of a credentials entry in `~/.aws/credentials`.

This script will only work if `dehydrated` if using the following `config` settings.
```
CHALLENGETYPE="dns-01"
HOOK=hook.sh
HOOK_CHAIN="no"
```

Note that `dehydrated` does not tell the hook script the challenge type, so this hook script has to assume every domain name is using a dns-01 challenge.

*Neither dehydrated nor this script needs to run as root, so don't do it!*
