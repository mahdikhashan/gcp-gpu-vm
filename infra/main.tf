provider "google" {
  project = "acoustic-alpha-308609"
  region  = "asia-southeast1"
}

# Random ID for unique names
resource "random_id" "id" {
  byte_length = 4
}

# Dedicated service account for GPU worker
resource "google_service_account" "gpu_worker_sa" {
  account_id   = "gpu-worker-sa"
  display_name = "GPU Worker Service Account"
}

# Grant broad Cloud Platform access (adjust roles if needed)
resource "google_project_iam_member" "gpu_worker_sa_binding" {
  project = "acoustic-alpha-308609"
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.gpu_worker_sa.email}"
}

# Storage bucket for audio files
resource "google_storage_bucket" "media_bucket" {
  name                        = "whisper-media-pipeline-${random_id.id.hex}"
  location                    = "asia-southeast1"
  force_destroy               = true
  uniform_bucket_level_access = true
}

# Pub/Sub topic for processing
resource "google_pubsub_topic" "whisper_tasks" {
  name = "whisper-tasks-${random_id.id.hex}"
}

# Pub/Sub subscription for GPU worker
resource "google_pubsub_subscription" "whisper_sub" {
  name                 = "sub-transcribe-gpu-worker-${random_id.id.hex}"
  topic                = google_pubsub_topic.whisper_tasks.name
  ack_deadline_seconds = 600
}

# Get project number for GCS service account
data "google_project" "current" {}

# IAM binding for GCS to publish to Pub/Sub
resource "google_pubsub_topic_iam_binding" "gcs_publisher" {
  topic = google_pubsub_topic.whisper_tasks.id
  role  = "roles/pubsub.publisher"

  members = [
    "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
  ]
}

# Storage notification for .wav uploads
resource "google_storage_notification" "wav_notification" {
  bucket         = google_storage_bucket.media_bucket.name
  topic          = google_pubsub_topic.whisper_tasks.id
  payload_format = "JSON_API_V1"
  event_types    = ["OBJECT_FINALIZE"]

  custom_attributes = {
    suffix = ".wav"
  }

  depends_on = [google_pubsub_topic_iam_binding.gcs_publisher]
}

# GPU compute instance
resource "google_compute_instance" "gpu_worker" {
  name         = "whisper-l4-worker"
  zone         = "asia-southeast1-a"
  machine_type = "g2-standard-4"

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
    network       = "default"
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

  metadata_startup_script = <<-EOT
#!/bin/bash
apt-get update
apt-get install -y ffmpeg
pip install --upgrade pip
pip install google-cloud-pubsub google-cloud-storage faster-whisper
EOT
}

# Outputs
output "bucket_name" {
  value = google_storage_bucket.media_bucket.name
}

output "pubsub_topic" {
  value = google_pubsub_topic.whisper_tasks.name
}

output "gpu_instance" {
  value = google_compute_instance.gpu_worker.name
}

output "gpu_service_account" {
  value = google_service_account.gpu_worker_sa.email
}
