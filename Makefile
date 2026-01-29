init:
	cd infra && \
	terraform init

setup-instance:
	cd infra && \
	terraform apply

fmt:
	cd infra && \
	terraform fmt

remove-infra:
	cd infra && \
	terraform destroy
