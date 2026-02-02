provider "google" {
  project = "acoustic-alpha-308609"
  region  = "asia-southeast1"
}

resource "google_compute_firewall" "allow_http" {
  name = "allow-http"
  network = "default"

  direction = "INGRESS"
  priority = 1000

  allow {
    protocol = "tcp"
    ports = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

resource "google_compute_instance" "gpu_worker" {
  name         = var.gpu_worker_name
  zone         = var.gpu_worker_zone
  machine_type = var.gpu_worker_type

  tags = ["http-server"]

  boot_disk {
    initialize_params {
      image = "projects/deeplearning-platform-release/global/images/common-cu128-ubuntu-2204-nvidia-570-v20251216"
      size  = 100
      type  = "pd-ssd"
    }
  }

  guest_accelerator {
    type  = "nvidia-l4"
    count = 1
  }

  network_interface {
    network = "default"
    access_config {}
  }

  service_account {
    email  = "gpu-worker-sa@acoustic-alpha-308609.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = true
  }

  metadata = {
    install-nvidia-driver = "True"
  }

  metadata_startup_script = file("../startupscript.sh")
}

output "gpu_instance" {
  value = google_compute_instance.gpu_worker.name
}
