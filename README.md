# Hub network

Using [Microsoft recommended Hub-Spoke network topology](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke) this module deployes the hub vnet. It should be deployed in the Common subscription account and only one hub per region. If deploying to multiple regions each of them should have one hub each. There is currently not added any peering between hubs, but would be preferred if each region was separate and using a traffic manager in front of them to support multi-region setup. That would also support multi cloud.

![hub topology](../../../docs/images/hub-network.png)

## DDos protection plan

Deploys one [ddos protection plan](https://docs.microsoft.com/en-us/azure/virtual-network/ddos-protection-overview) per region to offer full protection together with Azure Application Gateway with WAF.

It uses the premium DDos protection plan that offers more advanced protection, but at a cost. Since only one is required per region that should not increase cost too much.

Coupled together with Azure Application Gateway WAF it provides [full layer 3 to layer 7 mitigation capabilities](https://docs.microsoft.com/en-us/azure/virtual-network/ddos-protection-overview#types-of-ddos-attacks-that-ddos-protection-standard-mitigates).

## Network watcher

Deploys one network watcher per region to monitor network traffic. All network security groups activate NSG Flow logs to capture traffic flow.

## Virtual Gateway

Virtual Gateway supports both site-to-site and point-to-site connections. Point-to-site is useful for managing infrastructure if not on Avinor network.

Certificates for VPN will be stored in Key Vault where only key vault managers have access. To create a new client certificate see `infrastructure-live` repo for scripts to generate certificate. See [Microsoft guide](https://docs.microsoft.com/en-us/azure/vpn-gateway/point-to-site-vpn-client-configuration-azure-cert) for how to connect with point-to-site VPN.

## Storage account

All flow logs are stored in a storage account creted by hub. Since flow logs do not support using service endpoints at the moment it cannot use network policy to restrict access. This might be implemented later and will be activated when possible.

## Subnets

Creates 3 subnets by default: gateway, firewall and management (mgmt). For public endpoints there should also exist one public subnet, but this has to be created by the spoke so each spoke has its own public subnet.

Definitions:

| Name       | Description |
|------------|-------------|
| VNet hub   | Hub network address space, does not include any spokes
| VNet local | All local vnets, include hub and all spokes
| Firewall   | IP Address of firewall
| Gateway    | Incoming connections from gateway

### Public

Public subnet allows public ip's and route all traffic to internal network through firewall. This is where Application Gateways will be placed to protect incoming traffic.

To deploy multiple gateways create one public subnet for each gateway to support v2 of gateways. Currently v2 does not support UDR, but to should create subnets so they support it when available.

Application Gateways require certain ports open, see https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-faq#are-network-security-groups-supported-on-the-application-gateway-subnet

#### Routing

| Address space | Next hop |
|---------------|----------|
| VNet local    | Firewall |
| 0.0.0.0/0     | Internet |

#### Network security groups

| Source            | Destination   | Policy |
|-------------------|---------------|--------|
| Internet          | *:80          | Allow  |
| Internet          | *:443         | Allow  |
| AzureLoadBalancer | *             | Allow  |
| *                 | *:65503-65534 | Allow  |

### Management (Private dmz)

Management network should only access ssh connections from gateway. This is used to manage the the internal Azure resources.

**NB!!** Until gateway is properly configured it also accepts ssh from firewall configured with DNAT to forward ssh requests to jumphost.

#### Routing

| Address space | Next hop |
|---------------|----------|
| 0.0.0.0/0     | Firewall |

#### Network security groups

| Source            | Destination   | Policy |
|-------------------|---------------|--------|
| Firewall          | VNet local:22 | Allow  |
| Gateway           | VNet local:22 | Allow  |

### Firewall

Firewall network can only contain firewall resource and controls all traffic in and out of spoke networks. To control traffic firewall subnet have all service endpoints enabled. This allows it to monitor traffic to those services, but still take advantage of service endpoints performance and network restrictions.

#### Routing

| Address space | Next hop   |
|---------------|------------|
| VNet local    | VNet local |
| 0.0.0.0/0     | Internet   |

#### Network security groups

Firewall subnet does not support Network security groups.

### Gateway

Gateway subnet controls all traffic from VPN, site-to-site and point-to-site.

#### Routing

| Address space | Next hop   |
|---------------|------------|
| VNet local    | Firewall |
| 0.0.0.0/0     | Internet   |

#### Network security groups

Gateway subnet does not support Network security groups.