# acs-engine-terraform
Azure Container Service (ACS) Engine running K8s and provisioned by Terraform.

See my detailed article on [Terraform, Kubernetes and Microsoft Azure](http://danielrhoades.com/) to understand how to use it.  But if you are feeling lazy, then do the following steps to get it working:

Some pre-requisites first:

* Clone this project on your local machine;
* [Install Terraform](https://www.terraform.io/intro/getting-started/install.html);
* [Install Azure CLI 2.0](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (which is still in technical preview);
* Once installed check you have logged via `$ az login`;
* [Install K8s CLI](https://kubernetes.io/docs/tasks/kubectl/install/);
* [Install the ACS Engine locally](https://github.com/Azure/acs-engine/blob/master/docs/acsengine.md#downloading-and-building-acs-engine-locally) we will use this to generate an Azure Resource Template for the K8s cluster;
* [Generate an SSH key](https://github.com/Azure/acs-engine/blob/master/docs/ssh.md#ssh-key-generation) this will be given to VMs that get created in the cluster;
* Follow [Terraform's Azure setup guide, using the Azure CLI](https://www.terraform.io/docs/providers/azurerm/index.html#to-create-using-azure-cli), this will give you the subscription/tenant/client id/client secret you'll need in a moment.

Next, create a Terraform variables file (e.g. `k8s.tfvars`) with the following information:

```hcl-terraform
azure_subscription_id = "<YOUR-AZURE-SUBSCRIPTION-ID-FOR-TERRAFORM>"
azure_tenant_id       = "<YOUR-AZURE-TENANT-ID-FOR-TERRAFORM>"
azure_client_id       = "<YOUR-AZURE-CLIENT-ID-FOR-TERRAFORM>"
azure_client_secret   = "<YOUR-AZURE-CLIENT-SECRET-FOR-TERRAFORM>"

dns_prefix                      = "<YOUR-DNS-PREFIX>"
ssh_key                         = "<YOUR-SSH-KEY>"
```

If you followed [Terraform's Azure setup guide](https://www.terraform.io/docs/providers/azurerm/index.html), then you'll already have the values for each of the `azure_*` variables, so replace those placeholders.  The other substitutions should be made as follows:

* `YOUR-DNS-PREFIX` - Enter anything you like to prefix the DNS record for your cluster, e.g `dans-k8s-example`
* `YOUR-SSH-KEY` - The PEM encoded public version of the key you generated, e.g. just get the output from `cat ~/.ssh/id_rsa.pub`.

That should do it, so just run it now:

```bash
$ terraform apply -var-file="k8s.tfvars"
```

If the provisioning takes a long time, you might get an error, which will likely be due to a timeout.  If you can see 16 items in the resource group in the Azure portal and the rest of the steps in the guide work, it should be all fine. 

Once that's all done we can remotely connect to the cluster, to get the K8s remote configuration it's easier just to grab this from the master like so:
  
```bash
$ scp -i <SSH-KEY> azureuser@<MASTER-PUBLIC-IP>:~/.kube/config ~/.kube/config
```

In the above example you'll need to replace the placeholder values:

* `SSH-KEY` - Private SSH key matching the public key given to the cluster during setup, e.g. `~/.ssh/id_rsa`;
* `MASTER-PUBLIC-IP` - Find the master VM in the Azure portal, the public IP address will be attached to it.
 
Then test the connection using `kubectl get nodes`, which should return a list of our 2 nodes (1 master and 1 worker).  You're done, you can now deploy your own pods, for example:

```bash
$ kubectl run nginx --image nginx
$ kubectl expose deployments nginx --port=80 --type=LoadBalancer
$ kubectl get services
```

Wait until the nginx service has been given an external (public) IP.  In the background K8s is actually creating an Azure Load Balancer for this purpose (you can see it in the Azure portal).  Then simply confirm it works by running `curl http://<EXTERNAL-IP>`, you should get the standard nginx welcome page.  If `curl` just hangs then you probably forgot to manually fix that route I talked about above ;)

The lazy way to delete the setup when you are done is run:

```bash
$ az group delete --name "k8sexample"
```

You can't just run `terraform apply -var-file="k8s.tfvars"` unfortunately, because the setup of the K8s cluster via the ACS Engine is a bit of a hack at the moment.  Also, you might be best to manually delete `k8s_rendered.json` and the `_output` directory between runs.  If Terraform messes up then also delete the `terraform.tfstate`/`terraform.tfstate.backup` files.