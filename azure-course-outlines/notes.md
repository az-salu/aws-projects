Subnet Type | Needs Custom Route Table? | Why?
Public Subnet | ❌ No | Azure adds internet route by default
Private Subnet | ✅ Yes | You need NAT + manual internet route


🔍 In Azure, **AZ assignment happens at the resource level, not the subnet level.
Unlike AWS, where subnets are tied to specific AZs when created, Azure subnets are not tied to a zone by default. Instead, you choose the zone when you deploy a zonal resource like a VM, NAT Gateway, or Public IP.

dev-vnet
dev-nat-gateway-az1
public-ip-nat-az1
public-az1
public-az2
private-app-az1
private-app-az2
private-data-az1
private-data-az2

# Command
ssh -i private-key-pair azureuser@your-vm-public-ip




🔍 Where Are Azure’s Automatic Routes?
✅ 1. Azure Adds "System Routes" Behind the Scenes
These do not appear in the Route Tables blade, because they are not user-defined — but they do exist and are active at the subnet and network interface level.

To see them, you need to go to the effective routes view.

✅ How to View Routing (Including NAT and Internet Access)
🔁 Option A: View via Network Interface (NIC)
This is the most accurate way to inspect routing for a specific VM.

Go to Virtual Machines

Click your VM in the private or public subnet

Under Networking, click on the attached Network Interface

In the NIC pane, under Support + troubleshooting, click:
🔹 Effective routes

This will show:

System routes (e.g. 0.0.0.0/0 → Internet or → NAT Gateway)

User-defined routes (UDRs) if any were added

Routes to the VNet, BGP, and Azure services




A Blob Container in Azure is the equivalent of:

A bucket in AWS S3

A folder that stores binary large objects (BLOBs) — like .html, .zip, .jpg, .js, etc.

You upload your files into this container, and they get a unique URL that you can use to download or access them.


aosnoteprojectwebfiles
jupiter




✅ Azure vs AWS Storage Naming

AWS S3 | Azure Blob Storage
Bucket name (global unique) | Storage account name (global unique)
Object key | Blob name
Bucket path (e.g. folders) | Container name + Blob path




In Azure, Network Security Groups (NSGs) are the equivalent of Security Groups — but:

You associate NSGs to subnets or individual NICs (Network Interfaces), not directly to the VM or load balancer itself.

For Load Balancers, Azure has another concept called NSG + Load Balancer Rules.

For Bastion Hosts, Azure Bastion (the managed service) does not need you to create an NSG yourself unless you're managing your own jumpbox VM manually.


T
E
S
T