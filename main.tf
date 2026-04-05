variable "yc_cloud_id" {
  type        = string
  description = "terraform.tfvars"
}

variable "yc_folder_id" {
  type        = string
  description = "terraform.tfvars"
}

variable "public_ssh_key_path" {
  type        = string
  description = "Path to your public SSH key"
  default     = "./id_rsa.pub"
}

terraform {
  required_version = ">= 1.14.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.174.0"
    }
  }
}

provider "yandex" {
  cloud_id                 = var.yc_cloud_id
  folder_id                = var.yc_folder_id
  zone                     = "ru-central1-a"
  service_account_key_file = "auth.terraform.json"
}

resource "yandex_vpc_network" "network" {
  name = "netology-network"
}

resource "yandex_vpc_subnet" "subnet_public" {
  name           = "netology-subnet-public"
  zone           = "ru-central1-a"
  v4_cidr_blocks = ["192.168.10.0/24"]
  network_id     = yandex_vpc_network.network.id
}

resource "yandex_vpc_subnet" "subnet_private" {
  name           = "netology-subnet-private"
  zone           = "ru-central1-a"
  v4_cidr_blocks = ["192.168.20.0/24"]
  network_id     = yandex_vpc_network.network.id
  route_table_id = yandex_vpc_route_table.route_table_private.id
}

resource "yandex_vpc_security_group" "security_group" {
  name       = "netology-security-group"
  network_id = yandex_vpc_network.network.id

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "ANY"
    description    = "Allow all traffic from private subnet"
    v4_cidr_blocks = ["192.168.20.0/24"]
  }
}

resource "yandex_compute_instance" "compute_instance_nat" {
  name        = "netology-compute-instance-nat"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd80mrhj8fl2oe87o4e1"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_public.id
    ip_address         = "192.168.10.254"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.security_group.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.public_ssh_key_path)}"
  }
}

resource "yandex_vpc_route_table" "route_table_private" {
  name       = "netology-route-table-private"
  network_id = yandex_vpc_network.network.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = yandex_compute_instance.compute_instance_nat.network_interface[0].ip_address
  }
}

resource "yandex_compute_instance" "compute_instance_public_test" {
  name        = "netology-compute-instance-public-test"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd88m3uah9t47loeseir"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.security_group.id]

  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.public_ssh_key_path)}"
  }
}

resource "yandex_compute_instance" "private_test" {
  name        = "netology-compute-instance-private-test"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd88m3uah9t47loeseir"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_private.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.security_group.id]

  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.public_ssh_key_path)}"
  }
}

resource "yandex_storage_bucket" "storage_bucket" {
  bucket        = "netology-storage-bucket"
  force_destroy = true

  anonymous_access_flags {
    read        = true
    list        = false
    config_read = false
  }
}

resource "yandex_storage_object" "picture" {
  bucket       = yandex_storage_bucket.storage_bucket.bucket
  key          = "image.jpg"
  source       = "./image.jpg"
  content_type = "image/jpeg"
}

resource "yandex_iam_service_account" "service_account_instance_group_web" {
  name = "netology-iam-service-account-instance-group-web"
}

resource "yandex_resourcemanager_folder_iam_member" "resource_manager_service_account_instance_group_web" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.service_account_instance_group_web.id}"
}

resource "yandex_compute_instance_group" "compute_instance_group_web" {
  name                = "netology-compute-instance-group-web"
  folder_id           = var.yc_folder_id
  deletion_protection = false
  service_account_id  = yandex_iam_service_account.service_account_instance_group_web.id

  load_balancer {
    target_group_name = "netology-web-target-group"
  }

  instance_template {
    platform_id = "standard-v3"
    resources {
      cores  = 2
      memory = 2
    }
    boot_disk {
      initialize_params {
        image_id = "fd827b91d99psvq5fjit"
        size     = 10
      }
    }
    network_interface {
      network_id = yandex_vpc_network.network.id
      subnet_ids = [yandex_vpc_subnet.subnet_public.id]
      nat        = true
    }

    metadata = {
      ssh-keys  = "ubuntu:${file(var.public_ssh_key_path)}",
      user-data = <<-EOF
      #!/bin/bash
      cat > /var/www/html/index.html << 'END'
      <html>
      <body>
        <h1>Hello Cat</h1>
        <img src="https://${yandex_storage_bucket.storage_bucket.bucket_domain_name}/${yandex_storage_object.picture.key}">
      </body>
      </html>
      END
      systemctl restart apache2
      EOF
    }
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  deploy_policy {
    max_unavailable = 1
    max_expansion   = 1
  }

  allocation_policy {
    zones = ["ru-central1-a"]
  }

  health_check {
    interval = 30
    timeout  = 10
    tcp_options {
      port = 80
    }
  }

  depends_on = [yandex_storage_bucket.storage_bucket]
}

resource "yandex_lb_network_load_balancer" "load_balancer_web" {
  name = "netology-load-balancer-web"

  listener {
    name = "http-listener"
    port = 80

    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.compute_instance_group_web.load_balancer[0].target_group_id

    healthcheck {
      name                = "http-health-check"
      interval            = 30
      timeout             = 10
      unhealthy_threshold = 3
      healthy_threshold   = 3

      http_options {
        port = 80
        path = "/"
      }
    }
  }
}
