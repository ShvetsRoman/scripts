/ip firewall filter
add action=drop chain=input connection-state=invalid in-interface-list=WAN comment="drop invalid"
add action=accept chain=input connection-state=established,related in-interface-list=WAN comment="accept established,related"
add action=accept chain=input in-interface-list=WAN protocol=icmp comment="accept ICMP"

add chain=input protocol=tcp dst-port=2240,2241 src-address-list=FB-SSH-BAN action=drop comment="drop SSH BruteForce" disabled=no
add chain=input protocol=tcp dst-port=2240,2241 connection-state=new src-address-list=FB-SSH-3 action=add-src-to-address-list address-list=FB-SSH-BAN address-list-timeout=10d comment="" disabled=no
add chain=input protocol=tcp dst-port=2240,2241 connection-state=new src-address-list=FB-SSH-2 action=add-src-to-address-list address-list=FB-SSH-3 address-list-timeout=1m comment="" disabled=no
add chain=input protocol=tcp dst-port=2240,2241 connection-state=new src-address-list=FB-SSH-1 action=add-src-to-address-list address-list=FB-SSH-2 address-list-timeout=1m comment="" disabled=no
add chain=input protocol=tcp dst-port=2240,2241 connection-state=new action=add-src-to-address-list address-list=FB-SSH-1 address-list-timeout=1m comment="" disabled=no

add chain=input protocol=tcp dst-port=48291 src-address-list=FB-WB-BAN action=drop comment="drop WinBox BruteForce" disabled=no
add chain=input protocol=tcp dst-port=48291 connection-state=new src-address-list=FB-WB-3 action=add-src-to-address-list address-list=FB-WB-BAN address-list-timeout=10d comment="" disabled=no
add chain=input protocol=tcp dst-port=48291 connection-state=new src-address-list=FB-WB-2 action=add-src-to-address-list address-list=FB-WB-3 address-list-timeout=1m comment="" disabled=no
add chain=input protocol=tcp dst-port=48291 connection-state=new src-address-list=FB-WB-1 action=add-src-to-address-list address-list=FB-WB-2 address-list-timeout=1m comment="" disabled=no
add chain=input protocol=tcp dst-port=48291 connection-state=new action=add-src-to-address-list address-list=FB-WB-1 address-list-timeout=1m comment="" disabled=no
###
# Мої правила #
###
add action=drop chain=input connection-nat-state=!dstnat in-interface-list=WAN comment="drop all from WAN"

add action=fasttrack-connection chain=forward connection-state=established,related in-interface-list=WAN out-interface-list=LAN comment="fasttrack" 
add action=fasttrack-connection chain=forward connection-state=established,related in-interface-list=LAN out-interface-list=WAN

add action=drop chain=forward connection-state=invalid in-interface-list=WAN comment="drop invalid"
add action=accept chain=forward connection-state=established,related in-interface-list=WAN comment="accept established,related"
###
# Мої правила #
###
add action=drop chain=forward connection-nat-state=!dstnat in-interface-list=WAN comment="drop all from WAN"

/ip firewall nat
add chain=dstnat protocol=udp dst-port=53 action=redirect comment="redirect dns"
add chain=dstnat protocol=tcp dst-port=53 action=redirect

/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set api disabled=yes
set api-ssl disabled=yes

/ip neighbor discovery-settings
set discover-interface-list=LAN
