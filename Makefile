init:
	terraform -chdir=infra init

setup-instance:
	terraform -chdir=infra apply

fmt:
	terraform -chdir=infra fmt

remove-infra:
	terraform -chdir=infra destroy
