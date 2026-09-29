/interface bridge
add name=bridge1

/interface bridge port
add bridge=bridge1 interface=ether2
add bridge=bridge1 interface=ether3
add bridge=bridge1 interface=ether4
add bridge=bridge1 interface=ether5

/ip address
add address=192.168.88.22/24 interface=ether1
add address=192.168.1.1/24 interface=bridge1

/ip route
add dst-address=0.0.0.0/0 gateway=192.168.88.1

/ip firewall nat
add chain=srcnat out-interface=ether1 action=masquerade

/ip dns
set servers=8.8.8.8 allow-remote-requests=yes

/ip pool
add name=lan_pool ranges=192.168.1.2-192.168.1.30

/ip dhcp-server
add name=dhcp_lan interface=bridge1 address-pool=lan_pool disabled=no

/ip dhcp-server network
add address=192.168.1.0/24 gateway=192.168.1.1 dns-server=192.168.1.1

/ip firewall filter
add chain=input connection-state=established,related action=accept
add chain=input connection-state=invalid action=drop
add chain=input in-interface=ether1 action=drop

