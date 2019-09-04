# Example : AKS

This example deploys a virtual network hub that includes firewall rules to allow AKS cluster deployment. When deploying AKS behind Firewall it needs a set of rules configured, see [Microsoft documentation](https://docs.microsoft.com/en-us/azure/aks/limit-egress-traffic) for updated list.

At time of creating this the only way to successfully deploy this is to allow all 443 traffic out to Azure Cloud (or restricted to region of choice). Ideally it should be based on hostname, but Firewall will block traffic due to missing SNI extension.