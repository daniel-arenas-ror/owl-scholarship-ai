# Setup

Everything a human has to do that Claude can't (accounts, credentials, DNS).

> **Steps 2–8 are Phase 7 (deploy) and are deliberately on hold.** We're
> building the product locally first — see the [roadmap](https://claude.ai/code/artifact/c374c30e-89cb-42e2-b239-c331cabc32c7).
> Only step 1 (local dev) is needed for now.

## 1. Local development

```bash
# Docker Desktop must be running.
cp .env.example .env          # then set OPENAI_API_KEY (optional for Phase 0)
make setup                    # build images, create + migrate databases
make up                       # http://localhost:5173 · :3000 · :8000
```

`make test` / `make fmt` / `make lint` run across all three services in
containers, so a working local Ruby/Node/Python is not required.

## 2. Tooling for deployment

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform awscli gh   # or: brew install opentofu
```

## 3. AWS account

1. Create an IAM user with broad rights for the first `terraform apply`
   (AdministratorAccess is fine to start; tighten later).
2. `aws configure` with that user's access key.

## 4. Provision infrastructure

```bash
cd owl-infra
cp terraform.tfvars.example terraform.tfvars   # set region, domain, github_repo
terraform init
terraform apply
```

Creates: VPC + public subnet, security group, one `t4g.small` + Elastic IP,
three ECR repos, `/owl/*` SSM parameters (placeholder values), and — if
`github_repo` is set — the GitHub OIDC deploy role.

## 5. Real secrets into SSM

```bash
aws ssm put-parameter --name /owl/POSTGRES_PASSWORD  --type SecureString --overwrite --value "$(openssl rand -hex 16)"
aws ssm put-parameter --name /owl/OPENAI_API_KEY     --type SecureString --overwrite --value "sk-..."
aws ssm put-parameter --name /owl/RAILS_MASTER_KEY   --type SecureString --overwrite --value "$(cat owl-admin/config/master.key)"
aws ssm put-parameter --name /owl/OWL_JWT_PRIVATE_KEY --type SecureString --overwrite --value "$(cat owl-admin/config/jwt/private_key.pem)"
```

## 6. GitHub

1. Create the repo and push this monorepo to it.
2. **Settings → Secrets → Actions:** `AWS_DEPLOY_ROLE` =
   `terraform output -raw github_deploy_role_arn`.
3. **Settings → Variables → Actions:** `VITE_ADMIN_API_URL` =
   `https://admin.<domain>`, `VITE_OWL_API_URL` = `https://api.<domain>`.

## 7. First deploy

Push to `main`. The **CI** workflow lints and tests; **Deploy** builds the three
images, pushes them to ECR, sets `/owl/IMAGE_TAG`, and runs `/opt/owl/deploy.sh`
on the instance over SSM.

To deploy the very first time before DNS exists, you can also SSM in and run it:

```bash
aws ssm start-session --target "$(cd owl-infra && terraform output -raw instance_id)"
sudo /opt/owl/deploy.sh
```

## 8. DNS

```bash
cd owl-infra && terraform output nameservers   # set these at your registrar
```

Caddy issues Let's Encrypt certificates automatically once the names resolve to
the Elastic IP.
