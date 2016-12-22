# Dehydrated Route 53 Hook Script
This is a Dehydrated hook script that employs cli53 to enable dns-01 challenges with AWS Route 53 DNS hosting. The advantage of the dns-01 challenge is that doesn't require a web server or even for the server to be Internet accessible. Only the DNS hosting needs to be Internet accessible and have an API. So you can even request a certificate from an internal server which you only use internally.

```
Processing test.example.com
 + Signing domains...
 + Creating new directory /etc/dehydrated/certs/test.example.com ...
 + Generating private key...
 + Generating signing request...
 + Requesting challenge for test.example.com...
Creating challenge record for test.example.com in zone example.com
Created record: '_acme-challenge.test.example.com. 60 IN TXT "m4rWqTgOdEV7vRlxYvBhGi0_0w4BewR8SvrirMmv_vo"'
Waiting for sync.............................
Completed
 + Responding to challenge for test.example.com...
Deleting challenge record for test.example.com from zone example.com
1 record sets deleted
 + Challenge is valid!
 + Requesting certificate...
 + Checking certificate...
 + Done!
 + Creating fullchain.pem...
 + Done!
```

The `hook.sh` script can me used in conjunction with [`dehydrated`](https://github.com/lukas2511/dehydrated) and Let's Encrypt's service (letsencrypt.org) to issue SSL certificates for domain names hosted in [AWS Route 53](https://aws.amazon.com/route53/). The script is based on the dehydrated `hook.sh` template, and heavily leverages the excellent [`cli53` Route 53 client](https://github.com/barnybug/cli53). It is designed to be called by the `dehydrated` script to create and delete dns-01 challenge records.

The script will automatically identify the correct Route 53 zone for each domain name. It also supports certificates with alternative domain names in different Route 53 zones

## Dependencies

The script requires the following tools, all of which should be in your Linux distro, except probably `cli53` which is a single standalone binary with no dependencies.
- [cli53](https://github.com/barnybug/cli53)
- bash
- [jq](https://stedolan.github.io/jq/)
- sed
- xargs
- mailx (just for emailing errors)

This script will only work if `dehydrated` if using the following `config` settings.
```
CHALLENGETYPE="dns-01"
HOOK=hook.sh
HOOK_CHAIN="no"
```

`cli53` requires an AWS user access key (more details below).

You need to create a scheduled task (e.g. cron) to ensure your certificates are renewed regularly (more details below).

## AWS Route 53 IAM User and Policy

For `cli53` to work, it requires an AWS user access key with access to Route 53, with permissions
to list zones, and to create and delete records in zones. Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables, or create `~/.aws/credentials` file with `[default]` credentials, or set `AWS_PROFILE` to name of a credentials entry in `~/.aws/credentials`.

```
[default]
aws_access_key_id = AKIAJU5JT3POUSSXDY4A
aws_secret_access_key = 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
```

You can and should create an AWS IAM user, and attach just the minimum policy needed to support the dns-01 challenge process. You can either attached the standard 'AmazonRoute53FullAccess' policy, or you can create a more limited policy such as below and attach that.

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:ListHostedZonesByName"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListResourceRecordSets",
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": "arn:aws:route53:::hostedzone/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:GetChange"
            ],
            "Resource": "arn:aws:route53:::change/*"
        }
    ]
}
```

You could restrict this even further by listing only specific Route 53 zone Id's in, e.g.

```
"Resource": [ 
    "arn:aws:route53:::hostedzone/Z12345678901", 
    "arn:aws:route53:::hostedzone/Z12345678901" ]
```

## Scheduled Task for Renewals (cron)

Let's Encrypt certificate expire after 90 days, so you should create a cron task to check and renew the certificates if they will expire soon.

```
@daily /etc/dehydrated/dehydrated --cron  >/dev/null  #Check and renew SSL certificates from Let's Encrypt
```

## Limitations

`dehydrated` does not tell the hook script the challenge type, so this hook script has to assume every domain name is using a dns-01 challenge.
