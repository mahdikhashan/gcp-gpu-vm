#### Setup

```bash
terraform apply -var="project_id=jku-practical-project"
```

#### SSH

```bash
gcloud compute ssh --zone "asia-southeast1-a" "whisper-l4-worker" --project "jku-practical-project"
```