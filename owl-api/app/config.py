from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", extra="ignore")

    environment: str = "development"

    # Database
    owl_api_database_url: str = "postgresql+psycopg://owl:owl@localhost:5432/owl_api"

    # OpenAI
    openai_api_key: str = ""
    openai_chat_model: str = "gpt-4o-mini"
    openai_embedding_model: str = "text-embedding-3-small"

    # Phase 6 A/B: when a fine-tuned model id is set, this fraction of answer
    # turns (0.0-1.0) is routed to it instead of openai_chat_model. The router
    # (classification) always stays on the base model.
    owl_fine_tuned_model: str = ""
    owl_fine_tuned_traffic: float = 0.0

    # LangSmith
    langsmith_tracing: bool = False
    langsmith_api_key: str = ""
    langsmith_project: str = "owl-dev"

    # Trust boundary with owl-admin: RS256 JWTs verified against its JWKS
    owl_admin_jwks_url: str = "http://admin:3000/.well-known/jwks.json"
    owl_jwt_audience: str = "owl-api"
    owl_jwt_issuer: str = "owl-admin"

    # The reverse direction: owl-api calling owl-admin's Internal:: endpoints
    # (profile persistence, sending a conversation by email). A shared secret,
    # not JWT/JWKS — see app/owl_admin_client.py.
    owl_admin_url: str = "http://admin:3000"
    owl_internal_secret: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
