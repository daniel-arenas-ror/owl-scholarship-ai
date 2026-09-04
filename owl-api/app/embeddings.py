from langchain_openai import OpenAIEmbeddings

from app.config import get_settings


def _embedder() -> OpenAIEmbeddings:
    settings = get_settings()
    return OpenAIEmbeddings(
        model=settings.openai_embedding_model, api_key=settings.openai_api_key or None
    )


def embed_texts(texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    return _embedder().embed_documents(texts)


def embed_query(text: str) -> list[float]:
    return _embedder().embed_query(text)
