"""Phase 6 A/B: pick_answer_model routes a traffic fraction to a fine-tuned id."""

import app.llm as llm_module
from app.config import get_settings
from app.llm import pick_answer_model


def test_base_when_no_fine_tuned_model(monkeypatch):
    monkeypatch.setattr(get_settings(), "owl_fine_tuned_model", "")
    monkeypatch.setattr(get_settings(), "owl_fine_tuned_traffic", 1.0)
    monkeypatch.setattr(llm_module.random, "random", lambda: 0.0)

    model, variant = pick_answer_model()
    assert variant == "base"
    assert model.model_name == get_settings().openai_chat_model


def test_fine_tuned_when_in_traffic_slice(monkeypatch):
    monkeypatch.setattr(get_settings(), "owl_fine_tuned_model", "ft:gpt-4o-mini:acme::abc123")
    monkeypatch.setattr(get_settings(), "owl_fine_tuned_traffic", 0.5)
    monkeypatch.setattr(llm_module.random, "random", lambda: 0.1)  # < 0.5

    model, variant = pick_answer_model()
    assert variant == "finetuned"
    assert model.model_name == "ft:gpt-4o-mini:acme::abc123"


def test_base_when_outside_traffic_slice(monkeypatch):
    monkeypatch.setattr(get_settings(), "owl_fine_tuned_model", "ft:gpt-4o-mini:acme::abc123")
    monkeypatch.setattr(get_settings(), "owl_fine_tuned_traffic", 0.5)
    monkeypatch.setattr(llm_module.random, "random", lambda: 0.9)  # >= 0.5

    _model, variant = pick_answer_model()
    assert variant == "base"
