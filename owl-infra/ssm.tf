# Runtime configuration + secrets the EC2 host reads at deploy time.
# Terraform owns the *names*; real values are set out-of-band so they never
# land in state:
#
#   aws ssm put-parameter --name /owl/OPENAI_API_KEY --type SecureString \
#     --value 'sk-...' --overwrite
#
locals {
  # name => default placeholder value
  ssm_params = {
    ECR_REGISTRY           = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    IMAGE_TAG              = "latest"
    POSTGRES_USER          = "owl"
    POSTGRES_PASSWORD      = "CHANGE_ME"
    POSTGRES_DB            = "owl"
    OPENAI_API_KEY         = "CHANGE_ME"
    OPENAI_CHAT_MODEL      = "gpt-4o-mini"
    OPENAI_EMBEDDING_MODEL = "text-embedding-3-small"
    LANGSMITH_TRACING      = "false"
    LANGSMITH_API_KEY      = "CHANGE_ME"
    LANGSMITH_PROJECT      = "owl-prod"
    OWL_JWT_PRIVATE_KEY    = "CHANGE_ME" # PEM, single line with \n escapes
    RAILS_MASTER_KEY       = "CHANGE_ME"
    # Shared secret for owl-api -> owl-admin's Internal:: endpoints (profile
    # read/write, send-email). Must be the same value on both containers --
    # it's the same var name on each, so one SSM param covers both.
    OWL_INTERNAL_SECRET = "CHANGE_ME"
    # Optional: ConversationMailer's From: header. Falls back to
    # "Owl <owl@example.com>" in owl-admin if left blank.
    OWL_MAILER_FROM = ""
    OWL_DOMAIN      = var.domain
    ACME_EMAIL      = var.acme_email
  }
}

resource "aws_ssm_parameter" "runtime" {
  for_each = local.ssm_params

  name  = "${var.ssm_prefix}/${each.key}"
  type  = "SecureString"
  value = each.value

  # Real values are managed with `aws ssm put-parameter --overwrite`.
  lifecycle {
    ignore_changes = [value]
  }
}
