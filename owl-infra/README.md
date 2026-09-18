# owl-infra

Terraform for the single-EC2 deployment, plus the files that run on the host.

```
owl-infra/
├── *.tf                     # VPC, security group, EC2 + EIP, IAM, ECR, SSM, Route 53
├── instance/
│   ├── bootstrap.sh.tftpl   # EC2 user_data (installs Docker, writes the files below)
│   ├── docker-compose.prod.yml
│   ├── Caddyfile            # edge TLS + routing (apex → web, api.* → api, admin.* → admin)
│   ├── deploy.sh            # render .env from SSM, ECR login, compose pull + up
│   └── initdb/10-databases.sql
└── terraform.tfvars.example
```

## What you need locally

```bash
brew install terraform awscli   # or your package manager
aws configure                   # an IAM user with admin-ish rights for the first apply
```

## One-time setup

### 1. Remote state (recommended)

```bash
aws s3 mb s3://owl-tfstate-$(aws sts get-caller-identity --query Account --output text)
aws dynamodb create-table --table-name owl-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

Then uncomment the `backend "s3"` block in `versions.tf` and fill in the bucket.

### 2. Apply

```bash
cp terraform.tfvars.example terraform.tfvars   # edit region / domain
terraform init
terraform apply
```

This creates the VPC, the `t4g.small` instance with an Elastic IP, three ECR
repos, and the `/owl/*` SSM parameters (with placeholder values).

### 3. Set the real secrets in SSM

Terraform owns the parameter *names*; set values by hand so they never touch
state:

```bash
aws ssm put-parameter --name /owl/POSTGRES_PASSWORD   --type SecureString --overwrite --value "$(openssl rand -hex 16)"
aws ssm put-parameter --name /owl/OPENAI_API_KEY      --type SecureString --overwrite --value "sk-..."
aws ssm put-parameter --name /owl/RAILS_MASTER_KEY    --type SecureString --overwrite --value "$(cat ../owl-admin/config/master.key)"
aws ssm put-parameter --name /owl/OWL_JWT_PRIVATE_KEY --type SecureString --overwrite --value "$(cat ../owl-admin/config/jwt/private_key.pem)"
aws ssm put-parameter --name /owl/OWL_INTERNAL_SECRET --type SecureString --overwrite --value "$(openssl rand -hex 32)"
# OWL_DOMAIN / ACME_EMAIL are set from terraform.tfvars; override here if needed.
# OWL_MAILER_FROM is optional (falls back to a default in owl-admin) — no
# real SMTP/SES is wired up yet, so ConversationMailer#transcript won't
# actually send until that's configured; see the note in the main README.
```

### 4. First deploy

Images must exist in ECR before the host can start. Either push once by hand or
run the `deploy` GitHub Action (see `.github/workflows/`). Then:

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
sudo /opt/owl/deploy.sh
```

### 5. DNS (if you set `domain`)

```bash
terraform output nameservers   # set these at your registrar
```

Caddy gets Let's Encrypt certs automatically once DNS resolves to the EIP.

## Day-to-day

- **Shell on the box:** `aws ssm start-session --target <instance_id>`
- **Redeploy:** push to `main` (CI), or `sudo /opt/owl/deploy.sh` on the host
- **Change infra:** edit `*.tf`, `terraform apply`. Editing anything under
  `instance/` re-renders user_data and replaces the instance on the next apply.

## Cost

`t4g.small` + 30 GB gp3 + one Elastic IP ≈ **$18/mo** after any free-tier credit.
Set `min` nothing — this box runs 24/7 by design.
