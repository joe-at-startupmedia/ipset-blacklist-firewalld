#!/usr/bin/env bash
#
# usage update-blacklist.sh <configuration file>
# eg: update-blacklist.sh /etc/ipset-blacklist-firewalld/ipset-blacklist-firewalld.conf
#
function exists() { command -v "$1" >/dev/null 2>&1 ; }

function ipset_flush() {
  FLUSH_TMP=$(mktemp)
  firewall-cmd --permanent --ipset="$IPSET_BLACKLIST_NAME" --get-entries > "$FLUSH_TMP" 
  firewall-cmd --permanent --ipset="$IPSET_BLACKLIST_NAME" --remove-entries-from-file="$FLUSH_TMP"
  rm -f "$FLUSH_TMP"
}

if [[ -z "$1" ]]; then
  echo "Error: please specify a configuration file, e.g. $0 /etc/ipset-blacklist-firewalld/ipset-blacklist-firewalld.conf"
  exit 1
fi

# shellcheck source=ipset-blacklist-firewalld.conf
if ! source "$1"; then
  echo "Error: can't load configuration file $1"
  exit 1
fi

if ! exists curl && exists egrep && exists grep && exists firewall-cmd && exists sed && exists sort && exists wc ; then
  echo >&2 "Error: searching PATH fails to find executables among: curl egrep grep firewall-cmd sed sort wc"
  exit 1
fi

DO_OPTIMIZE_CIDR=no
if exists iprange && [[ ${OPTIMIZE_CIDR:-yes} != no ]]; then
  DO_OPTIMIZE_CIDR=yes
fi

if [[ ! -d $(dirname "$IP_BLACKLIST") ]]; then
  echo >&2 "Error: missing directory(s): $(dirname "$IP_BLACKLIST" |sort -u)"
  exit 1
fi

# create the ipset if needed (or abort if does not exists and FORCE=no)
if ! firewall-cmd --permanent --get-ipsets|command grep -q "$IPSET_BLACKLIST_NAME"; then
  if [[ ${FORCE:-no} != yes ]]; then
    echo >&2 "Error: ipset does not exist yet, add it using:"
    echo >&2 "# firewall-cmd --permanent --new-ipset=\"$IPSET_BLACKLIST_NAME\" --type=hash:net --option=family=inet --option=hashsize=\"${HASHSIZE:-16384}\" --option=maxelem=\"${MAXELEM:-65536}\""
    exit 1
  fi
  if ! firewall-cmd --permanent --new-ipset="$IPSET_BLACKLIST_NAME" --type=hash:net --option=family=inet --option=hashsize="${HASHSIZE:-16384}" --option=maxelem="${MAXELEM:-65536}"; then
    echo >&2 "Error: while creating the initial ipset"
    exit 1
  fi
fi

# add our ipset to drop zone sources (or abort if does not exists and FORCE=no)
if ! firewall-cmd --permanent $IPSET_DROP_ZONE --list-sources|command grep -q "ipset:$IPSET_BLACKLIST_NAME"; then
  # we may also have assumed that INPUT rule n°1 is about packets statistics (traffic monitoring)
  if [[ ${FORCE:-no} != yes ]]; then
    echo >&2 "Error: firewalld does not have the ipset added to the drop zone, add it using:"
    echo >&2 "# firewall-cmd --permanent $IPSET_DROP_ZONE --add-source=ipset:$IPSET_BLACKLIST_NAME"
    exit 1
  fi
  if ! firewall-cmd --permanent $IPSET_DROP_ZONE --add-source=ipset:"$IPSET_BLACKLIST_NAME"; then
    echo >&2 "Error: while adding ipset to the drop zone"
    exit 1
  fi
fi

# create a rich rule for the ipset drop zone source (default if none specified)
if [ "$IPSET_DROP_ZONE" != "--zone=drop" ] && ! firewall-cmd --permanent $IPSET_DROP_ZONE --list-rich-rules|command grep -q "ipset=$IPSET_BLACKLIST_NAME"; then
  if [[ ${FORCE:-no} != yes ]]; then
    echo >&2 "Error: firewalld does not have the source added to the drop zone, add it using:"
    echo >&2 "# firewall-cmd --permanent $IPSET_DROP_ZONE --add-rich-rule='rule source ipset=$IPSET_BLACKLIST_NAME drop'"
    exit 1
  fi
  if ! firewall-cmd --permanent $IPSET_DROP_ZONE --add-rich-rule="rule source ipset=$IPSET_BLACKLIST_NAME drop"; then
    echo >&2 "Error: while adding ipset source to the drop zone"
    exit 1
  fi
fi

IP_BLACKLIST_TMP=$(mktemp)
for i in "${BLACKLISTS[@]}"
do
  IP_TMP=$(mktemp)
  (( HTTP_RC=$(curl -L -A "blacklist-update/script/github" --connect-timeout 10 --max-time 10 -o "$IP_TMP" -s -w "%{http_code}" "$i") ))
  if (( HTTP_RC == 200 || HTTP_RC == 302 || HTTP_RC == 0 )); then # "0" because file:/// returns 000
    command grep -Po '^(?:\d{1,3}.){3}\d{1,3}(?:/\d{1,2})?' "$IP_TMP" | sed -r 's/^0*([0-9]+)\.0*([0-9]+)\.0*([0-9]+)\.0*([0-9]+)$/\1.\2.\3.\4/' >> "$IP_BLACKLIST_TMP"
    [[ ${VERBOSE:-yes} == yes ]] && echo -n "."
  elif (( HTTP_RC == 503 )); then
    echo -e "\\nUnavailable (${HTTP_RC}): $i"
  else
    echo >&2 -e "\\nWarning: curl returned HTTP response code $HTTP_RC for URL $i"
  fi
  rm -f "$IP_TMP"
done

# sort -nu does not work as expected
sed -r -e '/^(0\.0\.0\.0|10\.|127\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.|192\.168\.|22[4-9]\.|23[0-9]\.)/d' "$IP_BLACKLIST_TMP"|command egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}'|sort -n|sort -mu >| "$IP_BLACKLIST"
if [[ ${DO_OPTIMIZE_CIDR} == yes ]]; then
  if [[ ${VERBOSE:-no} == yes ]]; then
    echo -e "\\nAddresses before CIDR optimization: $(wc -l "$IP_BLACKLIST" | cut -d' ' -f1)"
  fi
  < "$IP_BLACKLIST" iprange --optimize - > "$IP_BLACKLIST_TMP" 2>/dev/null
  if [[ ${VERBOSE:-no} == yes ]]; then
    echo "Addresses after CIDR optimization:  $(wc -l "$IP_BLACKLIST_TMP" | cut -d' ' -f1)"
  fi
  cp "$IP_BLACKLIST_TMP" "$IP_BLACKLIST"
fi

rm -f "$IP_BLACKLIST_TMP"

ipset_flush
firewall-cmd --permanent --ipset="$IPSET_BLACKLIST_NAME" --add-entries-from-file="$IP_BLACKLIST"
firewall-cmd --reload

if [[ ${VERBOSE:-no} == yes ]]; then
  echo
  echo "Blacklisted addresses found: $(wc -l "$IP_BLACKLIST" | cut -d' ' -f1)"
fi
