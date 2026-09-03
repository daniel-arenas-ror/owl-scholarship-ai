from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", extra="ignore")

    environment: str = "development"

    # CORS: comma-separated origins allowed to call this API from a browser
    owl_web_origins: str = "http://localhost:5173"

    # Database
    owl_api_database_url: str = "postgresql+psycopg://owl:owl@localhost:5432/owl_api"

    # OpenAI
    openai_api_key: str = ""
    openai_chat_model: str = "gpt-4o-mini"
    openai_embedding_model: str = "text-embedding-3-small"

    # LangSmith
    langsmith_tracing: bool = False
    langsmith_api_key: str = ""
    langsmith_project: str = "owl-dev"

    # Trust boundary with owl-admin
    owl_internal_token: str = "dev-internal-token-change-me"
    owl_admin_jwks_url: str = "http://owl-admin:3000/.well-known/jwks.json"
    owl_jwt_audience: str = "owl-api"
    owl_jwt_issuer: str = "owl-admin"


@lru_cache
def get_settings() -> Settings:
    return Settings()
