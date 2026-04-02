### This is the Terraform-generated header for quepid-dev.
ECR_NAME_DEV := quepid-dev
ECR_URL_DEV := 222053980223.dkr.ecr.us-east-1.amazonaws.com/quepid-dev
CPU_ARCH ?= $(shell cat .aws-architecture 2>/dev/null || echo "linux/amd64")
### End of Terraform-generated header

.PHONY: help dist-dev publish-dev docker-clean service-redeploy-dev service-redeploy-stage service-redeploy-prod

help: ## Print this message
	@awk 'BEGIN { FS = ":.*##"; print "Usage:  make <target>\n\nTargets:" } \
		/^[-_[:alpha:]]+:.?*##/ { printf "  %-15s%s\n", $$1, $$2 }' $(MAKEFILE_LIST)

### Terraform-generated Developer Deploy Commands for Dev environment ###
check-arch:
	@ARCH_FILE=".aws-architecture"; \
	if [[ "$(CPU_ARCH)" != "linux/amd64" && "$(CPU_ARCH)" != "linux/arm64" ]]; then \
        echo "Invalid CPU_ARCH: $(CPU_ARCH)"; exit 1; \
    fi; \
	if [[ -f $$ARCH_FILE ]]; then \
		echo "latest-$(shell echo $(CPU_ARCH) | cut -d'/' -f2)" > .arch_tag; \
	else \
		echo "latest" > .arch_tag; \
	fi

dist-dev: check-arch ## Build docker container (intended for developer-based manual build)
	@ARCH_TAG=$$(cat .arch_tag); \
	docker buildx inspect $(ECR_NAME_DEV) >/dev/null 2>&1 || docker buildx create --name $(ECR_NAME_DEV) --use; \
	docker buildx use $(ECR_NAME_DEV); \
	docker buildx build --platform $(CPU_ARCH) \
		--file "Dockerfile.prod" \
		--load \
	    --tag $(ECR_URL_DEV):$$ARCH_TAG \
	    --tag $(ECR_URL_DEV):make-$$ARCH_TAG \
		--tag $(ECR_URL_DEV):make-$(shell git describe --always) \
		--tag $(ECR_NAME_DEV):$$ARCH_TAG \
		.

publish-dev: dist-dev ## Build, tag and push (intended for developer-based manual publish)
	@ARCH_TAG=$$(cat .arch_tag); \
	aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $(ECR_URL_DEV); \
	docker push $(ECR_URL_DEV):$$ARCH_TAG; \
	docker push $(ECR_URL_DEV):make-$$ARCH_TAG; \
	docker push $(ECR_URL_DEV):make-$(shell git describe --always); \
    echo "Cleaning up dangling Docker images..."; \
    docker image prune -f --filter "dangling=true"

docker-clean: ## Clean up Docker detritus
	@ARCH_TAG=$$(cat .arch_tag); \
	echo "Cleaning up Docker leftovers (containers, images, builders)"; \
	docker rmi -f $(ECR_URL_DEV):$$ARCH_TAG; \
	docker rmi -f $(ECR_URL_DEV):make-$$ARCH_TAG; \
	docker rmi -f $(ECR_URL_DEV):make-$(shell git describe --always) || true; \
    docker rmi -f $(ECR_NAME_DEV):$$ARCH_TAG || true; \
	docker buildx rm $(ECR_NAME_DEV) || true
	@rm -rf .arch_tag

### After a container is deployed via GHA to ECR in an AWS Account, the service will
### need to be redeployed to pick up the new container. The command below assumes that
### the user has already authenticated to the appropriate AWS account using the 
### QuepidManagers IdC role.
service-redeploy-dev: ## Redeploy the quepid service in Dev1 to use latest image from ECR 
	aws ecs update-service \
		--cluster $$(aws ecs list-clusters --output text | grep quepid-ecs-dev | cut -d'/' -f2) \
		--service $$(aws ecs list-services --cluster $$(aws ecs list-clusters --output text | grep quepid-ecs-dev | cut -d'/' -f2) \--output text | grep quepid | cut -d'/' -f3) \
		--force-new-deployment

service-redeploy-stage: ## Redeploy the quepid service in Stage-Workloads to use latest image from ECR
	aws ecs update-service \
		--cluster $$(aws ecs list-clusters --output text | grep quepid-ecs-stage | cut -d'/' -f2) \
		--service $$(aws ecs list-services --cluster $$(aws ecs list-clusters --output text | grep quepid-ecs-stage | cut -d'/' -f2) \--output text | grep quepid | cut -d'/' -f3) \
		--force-new-deployment

service-redeploy-prod: ## Redeploy the quepid service in Stage-Workloads to use latest image from ECR
	aws ecs update-service \
		--cluster $$(aws ecs list-clusters --output text | grep quepid-ecs-prod | cut -d'/' -f2) \
		--service $$(aws ecs list-services --cluster $$(aws ecs list-clusters --output text | grep quepid-ecs-prod | cut -d'/' -f2) \--output text | grep quepid | cut -d'/' -f3) \
		--force-new-deployment
