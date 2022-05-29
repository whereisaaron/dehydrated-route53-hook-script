#!/bin/bash
set -e

#
# Dehydrated hook script that employs cli53 to enable dns-01 challenges with AWS Route 53
# - Will automatically identify the correct Route 53 zone for each domain name
# - Supports certificates with alternative names in different Route 53 zones
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
        cli53 rrcreate --append --wait "${ZONE}" "_acme-challenge.${DOMAIN}. 60 TXT ${TOKEN_VALUE}"
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

    # NOP
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

#
# This hook is called at the end of a dehydrated command and can be used
# to do some final (cleanup or other) tasks.
#
exit_hook() {
  :
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|exit_hook)$ ]]; then
  "$HANDLER" "$@"
else
  # Dealing with this_hookscript_is_broken__dehydrated_is_working_fine__please_ignore_unknown_hooks_in_your_script
  exit 0
fi
