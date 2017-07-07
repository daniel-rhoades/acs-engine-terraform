provider "azurerm" {
  subscription_id = "${var.azure_subscription_id}"
  client_id       = "${var.azure_client_id}"
  client_secret   = "${var.azure_client_secret}"
  tenant_id       = "${var.azure_tenant_id}"
}

# Azure Resource Group
resource "azurerm_resource_group" "default" {
  name     = "${var.resource_group_name}"
  location = "${var.azure_location}"
}

# Azure Virtual Network
resource "azurerm_virtual_network" "default" {
  name                = "${var.virtualnetworkname}"
  address_space       = ["${var.cidr}"]
  location            = "${var.azure_location}"
  resource_group_name = "${var.resource_group_name}"
  depends_on = ["azurerm_resource_group.default"]
}

# Azure Virtual Network -> Subnet
resource "azurerm_subnet" "default" {
  name                 = "${var.virtualnetworkname}_subnet"
  resource_group_name  = "${var.resource_group_name}"
  virtual_network_name = "${azurerm_virtual_network.default.name}"
  address_prefix       = "${var.cidr_subnet}"
  depends_on = ["azurerm_virtual_network.default"]
}

output "virtualnetwork_subnet_default_id" {
  value = "${azurerm_subnet.default.id}"
}

# ACS Engine Config
data "template_file" "acs_engine_config" {
  template = "${file(var.acs_engine_config_file)}"

  vars {
    master_vm_count = "${var.master_vm_count}"
    dns_prefix = "${var.dns_prefix}"
    vm_size = "${var.vm_size}"
    subnet_id = "${azurerm_subnet.default.id}"
    first_master_ip = "${var.first_master_ip}"
    worker_vm_count = "${var.worker_vm_count}"
    admin_user = "${var.admin_user}"
    ssh_key = "${var.ssh_key}"
    service_principle_client_id = "${var.azure_client_id}"
    service_principle_client_secret = "${var.azure_client_secret}"
  }

  depends_on = ["azurerm_subnet.default"]
}

# Locally output the rendered ACS Engine Config (after substitution has been performed)
resource "null_resource" "render_acs_engine_config" {
  provisioner "local-exec" {
    command = "echo '${data.template_file.acs_engine_config.rendered}' > ${var.acs_engine_config_file_rendered}"
  }

  depends_on = ["data.template_file.acs_engine_config"]
}

# Locally run the ACS Engine to produce the Azure Resource Template for the K8s cluster
resource "null_resource" "run_acs_engine" {
  provisioner "local-exec" {
    command = "acs-engine generate ${var.acs_engine_config_file_rendered}"
  }

  depends_on = ["null_resource.render_acs_engine_config"]
}

# Locally run the Azure 2.0 CLI to create the resource deployment
resource "null_resource" "deploy_acs" {
  provisioner "local-exec" {
    command = "az group deployment create --name ${var.cluster_name} --resource-group ${var.resource_group_name} --template-file ./$(find _output -name 'azuredeploy.json') --parameters @./$(find _output -name 'azuredeploy.parameters.json')"
  }

  depends_on = ["null_resource.run_acs_engine"]
}

# Locally run the Azure 2.0 CLI to fix the routes
resource "null_resource" "fix_routetable" {
  provisioner "local-exec" {
    command = "az network vnet subnet update --name ${azurerm_subnet.default.name} --resource-group ${var.resource_group_name} --vnet-name ${azurerm_virtual_network.default.name} --route-table $(az resource list --resource-group ${var.resource_group_name} --resource-type Microsoft.Network/routeTables | jq -r '.[] | .id')"
  }

  depends_on = ["null_resource.deploy_acs"]
}