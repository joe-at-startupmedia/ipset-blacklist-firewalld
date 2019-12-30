ipset-blacklist-firewalld
===============

A Bash shell script which uses firewall-cmd to ban a large number of IP addresses published in IP blacklists. firewalld ipset uses a hashtable to store/fetch IP addresses and thus the IP lookup is a lot (!) faster than thousands of sequentially parsed iptables ban rules.


## Quick start for Debian/Ubuntu based installations
1. wget -O /usr/local/sbin/update-blacklist.sh https://raw.githubusercontent.com/joe-at-startupmedia/ipset-blacklist-firewalld/master/update-blacklist.sh
1. chmod +x /usr/local/sbin/update-blacklist.sh
1. mkdir -p /etc/ipset-blacklist-firewalld ; wget -O /etc/ipset-blacklist-firewalld/ipset-blacklist-firewalld.conf https://raw.githubusercontent.com/joe-at-startupmedia/ipset-blacklist-firewalld/master/ipset-blacklist-firewalld.conf
1. Modify ipset-blacklist-firewalld.conf according to your needs. Per default, the blacklisted IP addresses will be saved to /etc/ipset-blacklist-firewalld/ip-blacklist.restore
1. Auto-update the blacklist using a cron job

## First run, create the list
to generate the /etc/ipset-blacklist-firewalld/ip-blacklist.list
```
/usr/local/sbin/update-blacklist.sh /etc/ipset-blacklist-firewalld/ipset-blacklist-firewalld.conf
```

## iptables filter rule
```
# Enable blacklists
firewall-cmd --permanent --ipset --ipset=blacklist --add-entries-from-file=/etc/ipset-blacklist-firewalld/ip-blacklist.list
firewall-cmd --reload
```
Make sure to run this snippet in a firewall script or just insert it to /etc/rc.local.

## Cron job
In order to auto-update the blacklist, copy the following code into /etc/cron.d/update-blacklist. Don't update the list too often or some blacklist providers will ban your IP address. Once a day should be OK though.
```
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
33 23 * * *      root /usr/local/sbin/update-blacklist.sh /etc/ipset-blacklist-firewalld/ipset-blacklist-firewalld.conf
```

## Check for dropped packets
Using iptables, you can check how many packets got dropped using the blacklist:

```
drfalken@wopr:~# iptables -L INPUT -v --line-numbers
Chain INPUT (policy DROP 60 packets, 17733 bytes)
num   pkts bytes target            prot opt in  out source   destination
1       15  1349 DROP              all  --  any any anywhere anywhere     match-set blacklist src
2        0     0 fail2ban-vsftpd   tcp  --  any any anywhere anywhere     multiport dports ftp,ftp-data,ftps,ftps-data
3      912 69233 fail2ban-ssh-ddos tcp  --  any any anywhere anywhere     multiport dports ssh
4      912 69233 fail2ban-ssh      tcp  --  any any anywhere anywhere     multiport dports ssh
```

## Modify the blacklists you want to use
Edit the BLACKLIST array in /etc/ipset-blacklist-firewalld/ipset-blacklist-firewalld.conf to add or remove blacklists, or use it to add your own blacklists.
```
BLACKLISTS=(
"http://www.mysite.me/files/mycustomblacklist.txt" # Your personal blacklist
"http://www.projecthoneypot.org/list_of_ips.php?t=d&rss=1" # Project Honey Pot Directory of Dictionary Attacker IPs
# I don't want this: "http://www.openbl.org/lists/base.txt"  # OpenBL.org 30 day List
)
```
If you for some reason want to ban all IP addresses from a certain country, have a look at [IPverse.net's](http://ipverse.net/ipblocks/data/countries/) aggregated IP lists which you can simply add to the BLACKLISTS variable. For a ton of spam and malware related blacklists, check out this github repo: https://github.com/firehol/blocklist-ipsets

## Remove the firewall
```
firewall-cmd --permanent --delete-ipset=blacklist
firewall-cmd --zone=drop --remove-source=ipset:blacklist
firewall-cmd --reload
```
