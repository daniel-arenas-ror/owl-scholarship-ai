from langchain_openai import ChatOpenAI

from app.config import get_settings


def get_chat_model() -> ChatOpenAI:
    """The model the worker nodes stream answers from."""
    settings = get_settings()
    return ChatOpenAI(
        model=settings.openai_chat_model,
        api_key=settings.openai_api_key or None,
        temperature=0.3,
    )


def get_router_model() -> ChatOpenAI:
    """The model the router classifies turns with — temperature 0, no streaming
    needed. Same underlying model as the workers; a cheaper one could be swapped
    in here without touching the graph."""
    settings = get_settings()
    return ChatOpenAI(
        model=settings.openai_chat_model,
        api_key=settings.openai_api_key or None,
        temperature=0,
    )
