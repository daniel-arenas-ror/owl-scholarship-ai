r"""The graph: a structured-classifier router in front of four worker nodes.

    START -> route ->  general_advisor     -> END
                   |-> scholarship_expert  -> END
                   |-> profile_collector   -> END
                   \-> email_sender        -> END

``route`` makes one cheap, temperature-0 LLM call that tags the turn as
``general`` (broad advice, retrieval over everything), ``expert`` (the user
named one scholarship — retrieval is pinned to that ``scholarship_id`` and the
prompt is specialised), ``profile`` (the user is sharing personal info to
save), or ``email`` (the user wants this conversation sent to their inbox).

Two kinds of memory:
- A Postgres checkpointer holds conversation history, scoped to one
  ``thread_id`` (= one conversation).
- An ``InMemoryStore``, namespaced by ``user_id``, holds the student's profile
  (name, degrees — the durable copy lives in owl-admin's `users` table) so it
  carries across *different* conversations for the same person, not just
  within one. It's a read-through/write-through cache in front of that table:
  correctness never depends on it surviving a restart, only its speed does.
"""

import re
from typing import Annotated, Literal, TypedDict

from langchain_core.messages import AIMessage, BaseMessage, SystemMessage
from langchain_core.tools import tool
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages
from langgraph.store.base import BaseStore
from langgraph.store.memory import InMemoryStore
from langsmith import traceable
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select

from app.config import get_settings
from app.db import SessionLocal
from app.db_models import Scholarship
from app.llm import get_router_model, pick_answer_model
from app.owl_admin_client import OwlAdminError
from app.tools import (
    check_eligibility,
    get_scholarship_detail,
    load_user_profile,
    save_user_profile,
    search_scholarships,
    send_conversation_email,
)

GENERAL_SYSTEM_PROMPT = (
    "Eres Owl, un asistente que ayuda a estudiantes colombianos a encontrar becas. "
    "Responde en español, de forma breve y concreta, usando únicamente la "
    "información de becas provista a continuación. Si la información no alcanza "
    "para responder, dilo con honestidad en vez de inventar datos. "
    "Responde en texto plano: nada de Markdown (sin **negritas**, sin encabezados "
    "con #, sin listas con - o 1.) — la interfaz aún no interpreta ese formato."
)

EXPERT_SYSTEM_PROMPT = (
    "Eres Owl, y en esta conversación actúas como experto en UNA beca específica: "
    "«{title}» ({provider}). Responde en español, breve y concreto, SOLO sobre esta "
    "beca, usando la ficha y los fragmentos de abajo. Si te preguntan por otra beca, "
    "acláralo y ofrece ayuda general. No inventes fechas ni montos: si no están en la "
    "ficha, dilo. Texto plano, sin Markdown."
)

PROFILE_SYSTEM_PROMPT = (
    "Extrae del último mensaje del estudiante su nombre completo, teléfono, y/o "
    "títulos o carreras que haya estudiado, y guárdalos con la herramienta "
    "update_profile. Pasa solo los campos que el estudiante realmente mencionó en "
    "este mensaje; omite el resto. Si no menciona ningún dato nuevo, no llames la "
    "herramienta."
)

NO_DATA_MESSAGE = (
    "Aún no tengo becas cargadas. Cuando el equipo agregue oportunidades podré "
    "ayudarte a encontrar la más adecuada para tu perfil."
)

EXPERT_NOT_FOUND_MESSAGE = (
    "No encuentro los detalles de esa beca en este momento. ¿Quieres que te dé "
    "orientación general sobre becas similares?"
)

EMAIL_SENT_MESSAGE = "Listo, te envié la conversación a tu correo registrado."
EMAIL_FAILED_MESSAGE = "No pude enviar el correo en este momento. Intenta de nuevo en un rato."

TOP_K = 5
HISTORY_TURNS = 6
KNOWN_SCHOLARSHIPS_LIMIT = 60

# Words too generic to identify a scholarship on their own, so the name-match
# fallback skips them (otherwise "la beca X" matches every title with "beca").
_RESOLVE_STOPWORDS = {
    "beca",
    "becas",
    "convocatoria",
    "programa",
    "scholarship",
    "para",
    "sobre",
    "acerca",
    "estudios",
    "posgrado",
    "maestria",
    "maestría",
    "doctorado",
    "pregrado",
    "exterior",
}


class RouteDecision(BaseModel):
    """What the router LLM returns."""

    route: Literal["general", "expert", "profile", "email"] = Field(
        description=(
            "'expert' ONLY when the user asks about one specific, named scholarship. "
            "'profile' when the user shares or asks to save personal info (name, "
            "phone, degrees/education). 'email' when the user asks to receive this "
            "conversation by email. Otherwise 'general'."
        )
    )
    scholarship_query: str | None = Field(
        default=None,
        description="When route='expert', the scholarship name or provider the user named.",
    )


class AgentState(TypedDict):
    messages: Annotated[list, add_messages]
    citations: list[dict]
    user_context: dict
    route: str
    scholarship_id: str | None
    scholarship_title: str | None
    # Phase 6: the exact system message the answer was generated from, and which
    # model variant answered ("base" / "finetuned"). owl-admin persists both so
    # the fine-tuning export has real (system + context -> answer) examples.
    system_prompt: str
    model_variant: str
    # Which owl-admin identities this turn belongs to — set once per request in
    # app/routers/agent.py, read by profile_collector/email_sender and the
    # InMemoryStore hydration in the two advisor nodes.
    user_id: str
    conversation_id: str


# --- shared helpers -------------------------------------------------------------
def _has_scholarships() -> bool:
    with SessionLocal() as session:
        return bool(session.scalar(select(func.count()).select_from(Scholarship)))


def _known_scholarships() -> list[tuple[str, str]]:
    with SessionLocal() as session:
        rows = session.execute(
            select(Scholarship.title, Scholarship.provider).limit(KNOWN_SCHOLARSHIPS_LIMIT)
        ).all()
        return [(title, provider) for title, provider in rows]


def _resolve_scholarship(query: str | None) -> dict | None:
    """Best-effort map a name the router pulled out of the turn to a stored row."""
    text = (query or "").strip()
    if not text:
        return None

    tokens = sorted(
        (
            w
            for w in re.findall(r"[^\W_]{5,}", text, flags=re.UNICODE)
            if w.lower() not in _RESOLVE_STOPWORDS
        ),
        key=len,
        reverse=True,
    )

    with SessionLocal() as session:
        for needle in [text, *tokens]:
            row = session.scalar(
                select(Scholarship)
                .where(
                    or_(
                        Scholarship.title.ilike(f"%{needle}%"),
                        Scholarship.provider.ilike(f"%{needle}%"),
                    )
                )
                .limit(1)
            )
            if row is not None:
                return {
                    "id": str(row.id),
                    "title": row.title,
                    "provider": row.provider,
                    "source_url": row.source_url,
                }
    return None


def _format_user_context(user_context: dict | None) -> str:
    context = user_context or {}
    bits = []
    if context.get("country"):
        bits.append(f"país {context['country']}")
    if context.get("level"):
        bits.append(f"nivel {context['level']}")
    if context.get("fields"):
        bits.append("áreas " + ", ".join(context["fields"]))
    return f"\n\nPERFIL DEL ESTUDIANTE: {'; '.join(bits)}." if bits else ""


def _format_stored_profile(profile: dict | None) -> str:
    """The durable, cross-conversation profile — name/degrees only. Phone and
    email aren't relevant to scholarship advice, so they stay out of the prompt."""
    profile = profile or {}
    bits = []
    if profile.get("full_name"):
        bits.append(f"se llama {profile['full_name']}")
    if profile.get("degrees"):
        bits.append("tiene títulos en " + ", ".join(profile["degrees"]))
    return f"\n\nPERFIL GUARDADO DEL ESTUDIANTE: {'; '.join(bits)}." if bits else ""


def _hydrate_profile(store: BaseStore, user_id: str) -> dict:
    """Read-through cache: this process's InMemoryStore, backed by the durable
    `users` table. A cold cache costs one owl-admin round trip; nothing after
    that until this process restarts."""
    item = store.get(("users", user_id), "profile")
    if item is not None:
        return item.value
    profile = load_user_profile(user_id)
    store.put(("users", user_id), "profile", profile)
    return profile


def _remember_profile(store: BaseStore, user_id: str, **updates: object) -> dict:
    """Write-through: merge into the cached profile immediately, so the very
    next turn — even a brand new conversation for the same user — sees it
    without waiting on a re-fetch."""
    current = _hydrate_profile(store, user_id)
    merged = {**current, **{k: v for k, v in updates.items() if v is not None}}
    store.put(("users", user_id), "profile", merged)
    return merged


def _stream_answer(messages: list[BaseMessage]) -> tuple[AIMessage, str]:
    llm, variant = pick_answer_model()
    full = None
    for chunk in llm.stream(messages):
        full = chunk if full is None else full + chunk
    return (full if full is not None else AIMessage(content="")), variant


# --- nodes --------------------------------------------------------------------
@traceable(run_type="chain", name="classify_route")
def _classify_route(history: list[BaseMessage]) -> RouteDecision:
    catalogue = "\n".join(f"- {title} ({provider})" for title, provider in _known_scholarships())
    system = SystemMessage(
        content=(
            "Clasifica el ÚLTIMO mensaje del usuario en 'general', 'expert', 'profile' "
            "o 'email'.\n"
            "- 'expert': el usuario nombra UNA beca/programa concreto y quiere saber de ESE "
            "(requisitos, fechas, monto, cómo aplicar, 'cuéntame sobre X', 'háblame de X', "
            "'qué cubre X'). Aunque el nombre no esté en la lista, si nombra uno solo, es "
            "'expert'.\n"
            "- 'profile': el usuario comparte o pide guardar datos personales — su nombre, "
            "teléfono, o títulos/carreras que tiene (p. ej. 'me llamo…', 'mi teléfono es…', "
            "'estudié…', 'guarda mis datos').\n"
            "- 'email': el usuario pide que le envíes esta conversación por correo (p. ej. "
            "'envíame esto a mi correo', 'mándamelo por email').\n"
            "- 'general': orientación amplia, comparar varias, explorar por país/área/nivel, "
            "'qué becas hay para…', o cuando no aplica ninguna de las anteriores.\n"
            "Si es 'expert', pon en scholarship_query el nombre tal como lo escribió el "
            "usuario.\n\n"
            "Ejemplos:\n"
            "  'becas para maestría en Alemania' -> general\n"
            "  'cuéntame sobre DAAD' -> expert, scholarship_query='DAAD'\n"
            "  '¿requisitos de Chevening?' -> expert, scholarship_query='Chevening'\n"
            "  'compara Fulbright y Chevening' -> general\n"
            "  'me llamo Juan Pérez y estudié Ingeniería de Sistemas' -> profile\n"
            "  'mi teléfono es 3001234567' -> profile\n"
            "  'envíame esta conversación a mi correo' -> email\n\n"
            f"BECAS CONOCIDAS:\n{catalogue or '(ninguna)'}"
        )
    )
    router = get_router_model().with_structured_output(RouteDecision)
    return router.invoke([system, *history[-HISTORY_TURNS:]])


def route_node(state: AgentState) -> dict:
    empty = {"route": "general", "scholarship_id": None, "scholarship_title": None}

    # Only the API key gates classification entirely — an empty scholarships
    # table shouldn't block profile/email routing, only the two nodes that
    # actually need scholarships to answer with (each checks that itself).
    if not get_settings().openai_api_key:
        return empty

    try:
        decision = _classify_route(state["messages"])
    except Exception:  # noqa: BLE001 - a router failure must never break the turn
        return empty

    if decision.route != "expert":
        return {"route": decision.route, "scholarship_id": None, "scholarship_title": None}

    match = _resolve_scholarship(decision.scholarship_query)
    if match is None:
        return empty

    return {"route": "expert", "scholarship_id": match["id"], "scholarship_title": match["title"]}


_ROUTE_TO_NODE = {
    "expert": "scholarship_expert",
    "profile": "profile_collector",
    "email": "email_sender",
}


def _pick_route(state: AgentState) -> str:
    return _ROUTE_TO_NODE.get(state.get("route"), "general_advisor")


@traceable(run_type="chain", name="general_advisor")
def general_advisor_node(state: AgentState, *, store: BaseStore) -> dict:
    if not get_settings().openai_api_key or not _has_scholarships():
        return {"messages": [AIMessage(content=NO_DATA_MESSAGE)], "citations": []}

    profile = _hydrate_profile(store, state["user_id"])
    latest = state["messages"][-1]
    hits = search_scholarships(latest.content, k=TOP_K)

    context_blocks: list[str] = []
    citations: list[dict] = []
    seen: set[str] = set()
    for hit in hits:
        context_blocks.append(f"### {hit['title']} ({hit['provider']})\n{hit['snippet']}")
        if hit["scholarship_id"] not in seen:
            citations.append(
                {
                    "scholarship_id": hit["scholarship_id"],
                    "title": hit["title"],
                    "source_url": hit["source_url"],
                }
            )
            seen.add(hit["scholarship_id"])

    system = SystemMessage(
        content=f"{GENERAL_SYSTEM_PROMPT}{_format_user_context(state.get('user_context'))}"
        f"{_format_stored_profile(profile)}"
        "\n\nBECAS RELEVANTES:\n" + "\n\n".join(context_blocks)
    )
    answer, variant = _stream_answer([system, *state["messages"][-HISTORY_TURNS:]])
    return {
        "messages": [answer],
        "citations": citations,
        "system_prompt": system.content,
        "model_variant": variant,
    }


@traceable(run_type="chain", name="scholarship_expert")
def scholarship_expert_node(state: AgentState, *, store: BaseStore) -> dict:
    scholarship_id = state.get("scholarship_id")
    detail = get_scholarship_detail(scholarship_id) if scholarship_id else None
    if detail is None:
        return {"messages": [AIMessage(content=EXPERT_NOT_FOUND_MESSAGE)], "citations": []}

    profile = _hydrate_profile(store, state["user_id"])
    eligibility = check_eligibility(scholarship_id, state.get("user_context"))
    ficha = "\n".join(
        f"{label}: {value}"
        for label, value in (
            ("Proveedor", detail["provider"]),
            ("País", detail["country"]),
            ("Niveles", ", ".join(detail["levels"]) or "—"),
            ("Áreas", ", ".join(detail["fields"]) or "—"),
            ("Financiación", detail["funding_type"] or "—"),
            ("Monto", detail["amount_note"] or "—"),
            ("Fecha límite", detail["deadline"] or "—"),
            ("Elegibilidad", detail["eligibility_text"] or "—"),
        )
    )
    hint = f"\n\nSEÑALES DE ELEGIBILIDAD ({eligibility['status']}):\n- " + "\n- ".join(
        eligibility["reasons"]
    )
    body = "\n\n".join(detail["chunks"]) or detail["body_markdown"]

    system = SystemMessage(
        content=EXPERT_SYSTEM_PROMPT.format(title=detail["title"], provider=detail["provider"])
        + _format_user_context(state.get("user_context"))
        + _format_stored_profile(profile)
        + f"\n\nFICHA:\n{ficha}{hint}\n\nCONTENIDO:\n{body}"
    )
    answer, variant = _stream_answer([system, *state["messages"][-HISTORY_TURNS:]])
    citations = [
        {
            "scholarship_id": detail["scholarship_id"],
            "title": detail["title"],
            "source_url": detail["source_url"],
        }
    ]
    return {
        "messages": [answer],
        "citations": citations,
        "system_prompt": system.content,
        "model_variant": variant,
    }


@traceable(run_type="chain", name="profile_collector")
def profile_collector_node(state: AgentState, *, store: BaseStore) -> dict:
    if not get_settings().openai_api_key:
        return {"messages": [AIMessage(content=NO_DATA_MESSAGE)], "citations": []}

    user_id = state["user_id"]

    # A closure, not a module-level tool, so the LLM only ever sees full_name /
    # phone / degrees in its schema — user_id and the store are captured, never
    # something the model supplies itself.
    @tool
    def update_profile(
        full_name: str | None = None,
        phone: str | None = None,
        degrees: list[str] | None = None,
    ) -> str:
        """Save or update the student's full name, phone number, and/or academic
        degrees, for this and future conversations. Pass only the fields the
        student actually stated; omit the rest."""
        save_user_profile(user_id, full_name=full_name, phone=phone, degrees=degrees)
        _remember_profile(store, user_id, full_name=full_name, phone=phone, degrees=degrees)
        return "ok"

    llm = get_router_model().bind_tools([update_profile])
    system = SystemMessage(content=PROFILE_SYSTEM_PROMPT)
    response = llm.invoke([system, *state["messages"][-HISTORY_TURNS:]])

    captured: list[str] = []
    for call in response.tool_calls:
        if call["name"] != "update_profile":
            continue
        args = call["args"]
        update_profile.invoke(args)
        if args.get("full_name"):
            captured.append("tu nombre")
        if args.get("phone"):
            captured.append("tu teléfono")
        if args.get("degrees"):
            captured.append("tus títulos")

    if captured:
        confirmation = f"Ya tengo guardado {', '.join(captured)}. ¿En qué más te ayudo?"
    else:
        confirmation = (
            "Cuéntame tu nombre completo, tu teléfono o los títulos que tienes, y los "
            "guardo para futuras conversaciones."
        )

    return {
        "messages": [AIMessage(content=confirmation)],
        "citations": [],
        "system_prompt": PROFILE_SYSTEM_PROMPT,
        "model_variant": "base",
    }


@traceable(run_type="chain", name="email_sender")
def email_sender_node(state: AgentState) -> dict:
    try:
        send_conversation_email(state["conversation_id"])
        message = EMAIL_SENT_MESSAGE
    except OwlAdminError:
        message = EMAIL_FAILED_MESSAGE

    return {
        "messages": [AIMessage(content=message)],
        "citations": [],
        "system_prompt": "",
        "model_variant": "base",
    }


# --- assembly ---------------------------------------------------------------
def _build_graph() -> StateGraph:
    builder = StateGraph(AgentState)
    builder.add_node("route", route_node)
    builder.add_node("general_advisor", general_advisor_node)
    builder.add_node("scholarship_expert", scholarship_expert_node)
    builder.add_node("profile_collector", profile_collector_node)
    builder.add_node("email_sender", email_sender_node)
    builder.add_edge(START, "route")
    builder.add_conditional_edges(
        "route",
        _pick_route,
        {
            "general_advisor": "general_advisor",
            "scholarship_expert": "scholarship_expert",
            "profile_collector": "profile_collector",
            "email_sender": "email_sender",
        },
    )
    builder.add_edge("general_advisor", END)
    builder.add_edge("scholarship_expert", END)
    builder.add_edge("profile_collector", END)
    builder.add_edge("email_sender", END)
    return builder


def _to_psycopg_dsn(sqlalchemy_url: str) -> str:
    return sqlalchemy_url.replace("postgresql+psycopg://", "postgresql://")


_pool: ConnectionPool | None = None
_graph = None
_store: InMemoryStore | None = None


def init_graph() -> None:
    """Call once at app startup. Opens the checkpointer's own connection pool
    and creates its tables (idempotent), and starts this process's profile
    store (in-memory — see the module docstring)."""
    global _pool, _graph, _store

    dsn = _to_psycopg_dsn(get_settings().owl_api_database_url)
    _pool = ConnectionPool(
        conninfo=dsn,
        min_size=1,
        max_size=5,
        open=True,
        kwargs={"autocommit": True, "prepare_threshold": 0, "row_factory": dict_row},
    )
    checkpointer = PostgresSaver(_pool)
    checkpointer.setup()
    _store = InMemoryStore()
    _graph = _build_graph().compile(checkpointer=checkpointer, store=_store)


def close_graph() -> None:
    global _pool, _graph, _store
    if _pool is not None:
        _pool.close()
    _pool = None
    _graph = None
    _store = None


def get_graph():
    if _graph is None:
        raise RuntimeError("graph not initialized — call init_graph() during startup")
    return _graph


def build_graph_without_checkpointer():
    """A compiled graph with no Postgres checkpointer (a fresh InMemoryStore
    instead) — for evals and scripts that run one turn at a time and don't
    need conversation memory or cross-run profile memory."""
    return _build_graph().compile(store=InMemoryStore())
