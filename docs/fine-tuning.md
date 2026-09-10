# Fine-tuning loop (Phase 6)

The scaffolding for an SFT feedback loop. **Nothing runs automatically** — a
fine-tuning job costs real money and needs a real corpus, and right now there is
almost no data (a handful of 👍, no annotations). The point of this phase is to
have the whole path wired so it's a matter of `make` + one CLI once the
annotation view in `/admin` has collected enough real turns.

```
 /admin annotations + 👍/👎        owl-admin              owl-api
 ─────────────────────────    ───────────────────    ───────────────────────
  admin blesses a turn   ──►  fine_tuning:export  ──►  scripts/finetune.py
  (👍 / verdict:good /        sft-<ts>.jsonl           upload → create → status
   ideal_response)                                          │
                                                            ▼
                                                    fine_tuned_model id
                                                            │
        OWL_FINE_TUNED_MODEL + OWL_FINE_TUNED_TRAFFIC ◄──────┘
                    │
                    ▼
        a slice of answer turns runs on the tuned model;
        each turn records model_variant ("base" / "finetuned")
                    │
                    ▼
        python -m evals.run --model <id>   vs   base
        + 👍 ratio by variant in /admin/satisfaction
```

## 1. Collect data

Use Owl normally, then in `/admin/conversations/:id` mark answers: 👍/👎, and for
weak answers write the **ideal reply**. An assistant turn becomes a training
example when it has:

| Source | Training target |
| --- | --- |
| `annotation.ideal_response` present | the ideal reply (best signal — used even on a 👎) |
| `annotation.verdict = good` | the answer as-is |
| 👍 and no annotation | the answer as-is |

`👎` with no ideal reply is skipped (no usable target). owl-api persists the
exact system prompt (system + retrieved context) and which model answered on
`messages.generation`, so examples are real `(system + context → answer)` pairs.

## 2. Export the corpus (owl-admin)

```bash
make finetune-export        # → owl-admin/tmp/fine_tuning/sft-<ts>.jsonl (+ -val below 10 ex.)
```

OpenAI chat format, one object per line. It prints a per-reason breakdown, a
rough token count, and warns below OpenAI's 10-example floor.

## 3. Run the job (owl-api, manual, costs money)

```bash
docker compose exec api python -m scripts.finetune upload  tmp/sft.jsonl      # → train file id
docker compose exec api python -m scripts.finetune upload  tmp/sft-val.jsonl  # → val file id
docker compose exec api python -m scripts.finetune create <train-id> --val <val-id> --suffix owl-sft
docker compose exec api python -m scripts.finetune status <job-id>            # → fine_tuned_model id
```

(Copy the JSONL from `owl-admin/tmp/fine_tuning/` to somewhere the api container
can read, or just `docker compose cp`.)

## 4. Route traffic to it

```bash
# .env
OWL_FINE_TUNED_MODEL=ft:gpt-4o-mini-2024-07-18:owl:owl-sft:abc123
OWL_FINE_TUNED_TRAFFIC=0.2      # 20% of answer turns; the router stays on base
```

Every answer turn records `model_variant` on `messages.generation`, so
`/admin/satisfaction` can later split the 👍 ratio by variant.

## 5. Compare

```bash
python -m evals.run                                   # base, on the golden set
python -m evals.run --model ft:gpt-4o-mini:...:abc123 # the tuned model
```

Plus the live 👍 ratio by variant. The deliverable is a written before/after.

## Deployment (Phase 7)

Locally the model id is an env var. On AWS it belongs in SSM Parameter Store
(`/owl/openai/fine_tuned_model`, `/owl/openai/fine_tuned_traffic`), read the
same way `owl-api/app/config.py` reads every other setting.

## Still to do

- **DPO** from 👍/👎 pairs on similar prompts — the export only does SFT. Needs
  prompt-similarity clustering and enough contrasting pairs; revisit once there
  are dozens of each.
