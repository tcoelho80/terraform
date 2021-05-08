terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.25.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg_tarefa" {
  name     = "tarefaresources"
  location = "eastus"

  tags     = {
        "Environment" = "atividade 2"
    }
}

resource "azurerm_virtual_network" "vnet_tarefa" {
  name                = "tarefanetwork"
  resource_group_name = azurerm_resource_group.rg_tarefa.name
  location            = azurerm_resource_group.rg_tarefa.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "sbunet_tarefa" {
  name                 = "tarefasbunet"
  resource_group_name  = azurerm_resource_group.rg_tarefa.name
  virtual_network_name = azurerm_virtual_network.vnet_tarefa.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "ip_tarefa" {
  name                = "tarefapublicip"
  resource_group_name = azurerm_resource_group.rg_tarefa.name
  location            = azurerm_resource_group.rg_tarefa.location
  allocation_method = "Static"
}

resource "azurerm_network_security_group" "nsg_tarefa" {
  name                = "tarefasecuritygroup"
  resource_group_name = azurerm_resource_group.rg_tarefa.name
  location            = azurerm_resource_group.rg_tarefa.location
  
  security_rule {
        name                       = "mysql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface" "ni_tarefa" {
  name                = "tarefanetwork"
  resource_group_name = azurerm_resource_group.rg_tarefa.name
  location            = azurerm_resource_group.rg_tarefa.location
  

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sbunet_tarefa.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip_tarefa.id
  }
}

resource "azurerm_network_interface_security_group_association" "nisgs_tarefa" {
    network_interface_id      = azurerm_network_interface.ni_tarefa.id
    network_security_group_id = azurerm_network_security_group.nsg_tarefa.id
}

data "azurerm_public_ip" "ip_data_db" {
  name                = azurerm_public_ip.ip_tarefa.name
  resource_group_name = azurerm_resource_group.rg_tarefa.name
}

resource "azurerm_storage_account" "samsql" {
    name                        = "samsql"
    resource_group_name         = azurerm_resource_group.rg_tarefa.name
    location                    = azurerm_resource_group.rg_tarefa.location
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

resource "azurerm_linux_virtual_machine" "vm_tarefa" {
  name                = "tarefavm"
  resource_group_name = azurerm_resource_group.rg_tarefa.name
  location            = azurerm_resource_group.rg_tarefa.location
  network_interface_ids = [azurerm_network_interface.ni_tarefa.id]
  size                  = "Standard_DS1_v2"
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  computer_name  = "mytarefa"
  admin_username      = "azureuser"
  admin_password      = "thi11b65@mtg23"
  disable_password_authentication = false
  
  boot_diagnostics {
        storage_account_uri = azurerm_storage_account.samsql.primary_blob_endpoint
    }

    depends_on = [ azurerm_resource_group.rg_tarefa ]

}

output "public_ip_address_mysql" {
  value = azurerm_public_ip.ip_tarefa.ip_address
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.vm_tarefa]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = "azureuser"
            password = "thi11b65@mtg23"
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        source = "config"
        destination = "/home/azureuser"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "azureuser"
            password = "thi11b65@mtg23"
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/azureuser/config/user.sql",
            "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/config/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}



