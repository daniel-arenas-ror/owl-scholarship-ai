import random

from langchain_openai import ChatOpenAI

from app.config import get_settings


def get_chat_model(model: str | None = None) -> ChatOpenAI:
    """The model the worker nodes stream answers from. Pass `model` to pin one
    (evals do this to compare base vs fine-tuned)."""
    settings = get_settings()
    return ChatOpenAI(
        model=model or settings.openai_chat_model,
        api_key=settings.openai_api_key or None,
        temperature=0.3,
    )


def pick_answer_model() -> tuple[ChatOpenAI, str]:
    """Phase 6 A/B. Returns (model, variant) where variant is "finetuned" or
    "base". A fine-tuned id + a traffic fraction > 0 sends that share of turns to
    the fine-tuned model."""
    settings = get_settings()
    if settings.owl_fine_tuned_model and random.random() < settings.owl_fine_tuned_traffic:
        return get_chat_model(settings.owl_fine_tuned_model), "finetuned"
    return get_chat_model(), "base"


def get_router_model() -> ChatOpenAI:
    """The model the router classifies turns with — temperature 0, no streaming
    needed. Always the base model; classification isn't what we fine-tune."""
    settings = get_settings()
    return ChatOpenAI(
        model=settings.openai_chat_model,
        api_key=settings.openai_api_key or None,
        temperature=0,
    )
