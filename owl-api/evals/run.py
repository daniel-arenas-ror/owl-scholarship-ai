"""Local eval for the Phase 4 graph.

Runs every case in ``evals/golden.jsonl`` through the REAL graph — real router,
real retrieval, real OpenAI — against whatever scholarships are in your local
``OWL_API_DATABASE_URL``. So: run it after ``make seed`` with ``OPENAI_API_KEY``
set.

    make eval                        # route accuracy + retrieval hit-rate + must-mention
    python -m evals.run --verbose    # also print each answer
    python -m evals.run --judge      # + an LLM groundedness spot-check (extra calls)
    python -m evals.run --json       # machine-readable summary
    python -m evals.run --model ft:gpt-4o-mini:...   # run the answer turns on a
                                       fine-tuned model (Phase 6 base-vs-tuned compare)

Not wired into CI (no API key, no seeded data there). This is the harness a
LangSmith dataset + ``evaluate()`` run replaces once there's an account and real
transcripts to build a dataset from.
"""

import argparse
import json
import sys
from pathlib import Path

from langchain_core.messages import HumanMessage

from app.graph import build_graph_without_checkpointer
from app.tools import search_scholarships

GOLDEN = Path(__file__).parent / "golden.jsonl"
ROUTE_ACCURACY_MIN = 0.80
RETRIEVAL_HIT_RATE_MIN = 0.70

_graph = build_graph_without_checkpointer()


def _load_cases() -> list[dict]:
    with GOLDEN.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def _run_case(case: dict) -> dict:
    result = _graph.invoke(
        {
            "messages": [HumanMessage(content=case["question"])],
            "user_context": case.get("user_context", {}),
        }
    )
    return {
        "answer": result["messages"][-1].content,
        "route": result.get("route", "general"),
        "citations": [c["title"] for c in result.get("citations", [])],
    }


def _judge_grounded(question: str, answer: str) -> bool:
    from app.llm import get_chat_model

    snippets = "\n".join(
        f"- {hit['title']}: {hit['snippet']}" for hit in search_scholarships(question, k=5)
    )
    prompt = (
        "¿La RESPUESTA se apoya únicamente en los FRAGMENTOS? Responde solo SI o NO.\n\n"
        f"PREGUNTA: {question}\n\nFRAGMENTOS:\n{snippets}\n\nRESPUESTA: {answer}"
    )
    verdict = str(get_chat_model().invoke(prompt).content).strip().upper()
    return verdict.startswith(("SI", "SÍ", "YES"))


def _mark(value: bool | None) -> str:
    if value is None:
        return "·"
    return "✓" if value else "✗"


def _rate(values: list[bool]) -> float | None:
    return (sum(values) / len(values)) if values else None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true", help="print each answer")
    parser.add_argument("--judge", action="store_true", help="LLM groundedness spot-check")
    parser.add_argument("--json", action="store_true", dest="as_json", help="machine-readable")
    parser.add_argument("--model", help="pin the answer model (e.g. a fine-tuned id)")
    args = parser.parse_args()

    if args.model:
        # Force every answer turn onto this model, base-vs-tuned comparison.
        import app.graph as graph_module
        from app.llm import get_chat_model

        graph_module.pick_answer_model = lambda: (get_chat_model(args.model), "override")

    rows: list[dict] = []
    for case in _load_cases():
        got = _run_case(case)

        want_scholarship = case.get("expected_scholarship")
        cited = " | ".join(got["citations"]).lower()
        must_mention = case.get("must_mention", [])
        answer_lower = got["answer"].lower()

        rows.append(
            {
                "id": case["id"],
                "want_route": case["expected_route"],
                "route": got["route"],
                "route_ok": got["route"] == case["expected_route"],
                "retrieval_ok": (want_scholarship.lower() in cited) if want_scholarship else None,
                "mention_ok": (
                    all(m.lower() in answer_lower for m in must_mention) if must_mention else None
                ),
                "grounded": (
                    _judge_grounded(case["question"], got["answer"]) if args.judge else None
                ),
                "citations": got["citations"],
                "answer": got["answer"],
            }
        )

    route_accuracy = _rate([r["route_ok"] for r in rows]) or 0.0
    retrieval_hit_rate = _rate([r["retrieval_ok"] for r in rows if r["retrieval_ok"] is not None])
    mention_rate = _rate([r["mention_ok"] for r in rows if r["mention_ok"] is not None])
    grounded_rate = _rate([r["grounded"] for r in rows if r["grounded"] is not None])

    summary = {
        "cases": len(rows),
        "route_accuracy": route_accuracy,
        "retrieval_hit_rate": retrieval_hit_rate,
        "mention_rate": mention_rate,
        "grounded_rate": grounded_rate,
    }

    if args.as_json:
        print(json.dumps({**summary, "rows": rows}, ensure_ascii=False, indent=2))
    else:
        for r in rows:
            print(
                f"{_mark(r['route_ok'])} route  {_mark(r['retrieval_ok'])} retr  "
                f"{_mark(r['mention_ok'])} ment  {_mark(r['grounded'])} grnd   "
                f"[{r['id']}] {r['want_route']}→{r['route']}  cites={r['citations']}"
            )
            if args.verbose:
                print(f"     {r['answer']}\n")
        print()
        print(f"cases               {summary['cases']}")
        print(f"route accuracy      {route_accuracy:.0%}  (min {ROUTE_ACCURACY_MIN:.0%})")
        if retrieval_hit_rate is not None:
            print(
                f"retrieval hit-rate  {retrieval_hit_rate:.0%}  (min {RETRIEVAL_HIT_RATE_MIN:.0%})"
            )
        if mention_rate is not None:
            print(f"must-mention rate   {mention_rate:.0%}")
        if grounded_rate is not None:
            print(f"groundedness (LLM)  {grounded_rate:.0%}")

    passed = route_accuracy >= ROUTE_ACCURACY_MIN and (
        retrieval_hit_rate is None or retrieval_hit_rate >= RETRIEVAL_HIT_RATE_MIN
    )
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
