#!/bin/bash

#
# Dehydrated hook script that employs cli53 to enable dns-01 challenges with AWS Route 53
# - Will automatically identify the correct Route 53 zone for each domain name
# - Supports certificates with alternative names in different Route 53 zones
#
# This version includes a deploy_cert function for CentOS 6 / RHEL 6 for webmin and apache
#
# Aaron Roydhouse <aaron@roydhouse.com>, 2016
# https://github.com/whereisaaron/dehydrated-route53-hook-script
# Based on dehydrated hook.sh template
#
# Requires dehydrated (https://github.com/lukas2511/dehydrated)
# Requires cli53 (https://github.com/barnybug/cli53)
# Requires bash, jq, mailx, sed, xargs
#
# Requires AWS credentials with access to Route53, with permissions
# to list zones, and to create and delete records in zones.
#
# Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables, or
# Create ~/.aws/credentials file with [default] credentials, or
# Set AWS_PROFILE to name of credentials entry in ~/.aws/credentials
#
# Neither dehydrated nor this script needs to run as root, so don't do it!
#

#
# This hook is called once for every domain that needs to be
# validated, including any alternative names you may have listed.
#
# Creates TXT record is appropriate Route53 domain, and waits for it to sync
#
deploy_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    local ZONE=$(find_zone "${DOMAIN}")
    
    if [[ -n "$ZONE" ]]; then
        echo "Creating challenge record for ${DOMAIN} in zone ${ZONE}"
        cli53 rrcreate --replace --wait "${ZONE}" "_acme-challenge.${DOMAIN}. 60 TXT ${TOKEN_VALUE}"
    else
        echo "Could not find zone for ${DOMAIN}"
        exit 1
    fi
}

#
# This hook is called after attempting to validate each domain,
# whether or not validation was successful. Here you can delete
# files or DNS records that are no longer needed.
#
# Delete TXT record from appropriate Route53 domain, does not wait the deletion to sync
#
clean_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    local ZONE=$(find_zone "${DOMAIN}")
    
    if [[ -n "$ZONE" ]]; then
        echo "Deleting challenge record for ${DOMAIN} from zone ${ZONE}"
        cli53 rrdelete "${ZONE}" "_acme-challenge.${DOMAIN}." TXT
    else
        echo "Could not find zone for ${DOMAIN}"
        exit 1
    fi

    #
    # The parameters are the same as for deploy_challenge.
}

#
# This hook is called once for each certificate that has been
# produced. Here you might, for instance, copy your new certificates
# to service-specific locations and reload the service.
#
deploy_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"

    #
    # Restart webmin based on domain name match heuristic:
    # If the first segment of the primary certificate domain name 
    # matches the first segment of the hostname, then this certificate
    # may be used for webmin, so restart webmin service to read it
    # Requires that user running dehydrated has sudoer rights to execute the commands, e.g
    # dehydrated ALL = NOPASSWD: /sbin/service webmin restart
    #
 
    # Only consider restarting if webmin if it is installed and running
    if [[ "$(sudo service webmin status)" =~ "running" ]]; then

      # Restart webmin if the domain name somewhat matches the hostname
      if [[ "${DOMAIN}" =~ ^"$(hostname --short)"\. ]]; then
        echo "Restarting webmin to read the new certificate files for ${DOMAIN}"
        sudo service webmin restart
      fi

    fi

    #
    # Restart apache to read the new certificate files
    # Requires that user running dehydrated has sudoer rights to execute the commands, e.g
    # dehydrated ALL = NOPASSWD: /sbin/service httpd configtest, /sbin/service httpd graceful
    #

    # Only consider restarting if apache if it is installed and running
    if [[ "$(sudo service httpd status)" =~ "running" ]]; then

      # Restart apache if the configuration is valid
      echo -n "Checking apache config: "
      sudo service httpd configtest
      if [[ $? -eq 0 ]]; then
        echo "Restarting apache to read the new certificate files for ${DOMAIN}"
        sudo service httpd graceful
      else
        (>&2 echo "Skipping restarting apache because apache config is invalid") 
      fi

    fi
}

#
# This hook is called once for each certificate that is still
# valid and therefore wasn't reissued.
#
unchanged_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

    # NOP
}

#
# This hook is called if the challenge response has failed, so domain
# owners can be aware and act accordingly.
#
function invalid_challenge {
    local DOMAIN="${1}" RESPONSE="${2}"

    local HOSTNAME="$(hostname)"

    # Output error to stderr
    (>&2 echo "Failed to issue SSL cert for ${DOMAIN}: ${RESPONSE}")

    # Mail error to root user
    mailx -s "Failed to issue SSL cert for ${DOMAIN} on ${HOSTNAME}" root <<-END
      Failed to issue SSL cert for ${DOMAIN} on ${HOSTNAME}

      Error from verification server:
      ${RESPONSE}
END
}

#
# Remove one level from the front of a domain name
# Returns the rest of the domain name (success), or blank if nothing left (fail)
#
function get_base_name() {
    local HOSTNAME="${1}"

    if [[ "$HOSTNAME" == *"."* ]]; then
      HOSTNAME="${HOSTNAME#*.}"
      echo "$HOSTNAME"
      return 0
    else
      echo ""
      return 1
    fi
}

#
# Find the Route53 zone for this domain name
# Prefers the longest match, e.g. if creating 'a.b.foo.baa.com',
# a 'foo.baa.com' zone will be preferred over a 'baa.com' zone
# Returns the zone name (success) or nothing (fail)
#
function find_zone() {
  local DOMAIN="${1}"

  local ZONELIST=$(cli53 list -format json | jq --raw-output '.[].Name' | sed -e 's/\.$//' | xargs echo -n)

  local TESTDOMAIN="${DOMAIN}"

  while [[ -n "$TESTDOMAIN" ]]; do
    for zone in $ZONELIST; do
      if [[ "$zone" == "$TESTDOMAIN" ]]; then
        echo "$zone"
        return 0
      fi
    done
    TESTDOMAIN=$(get_base_name "$TESTDOMAIN")
  done

  return 1
}

HANDLER="$1"; shift
"$HANDLER" "$@"
