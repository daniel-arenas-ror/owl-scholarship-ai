from langchain_openai import ChatOpenAI

from app.config import get_settings


def get_chat_model() -> ChatOpenAI:
    settings = get_settings()
    return ChatOpenAI(
        model=settings.openai_chat_model,
        api_key=settings.openai_api_key or None,
        temperature=0.3,
    )
