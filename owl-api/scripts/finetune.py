"""Phase 6 — drive an OpenAI SFT fine-tuning job by hand.

The training corpus comes from owl-admin:

    docker compose exec admin bin/rails fine_tuning:export
    # writes owl-admin/tmp/fine_tuning/sft-<ts>.jsonl (+ a val split)

Then, from owl-api (needs OPENAI_API_KEY):

    python -m scripts.finetune upload  tmp/sft.jsonl
    python -m scripts.finetune create <train-file-id> --val <val-file-id> --suffix owl-sft
    python -m scripts.finetune status <job-id>
    python -m scripts.finetune list

On success `status` prints the fine_tuned_model id — set it as OWL_FINE_TUNED_MODEL
and give it a slice of traffic with OWL_FINE_TUNED_TRAFFIC (0.0-1.0).

This is deliberately a manual CLI: a fine-tuning job costs real money and needs a
real corpus, so nothing here runs automatically.
"""

import argparse
import sys

from openai import OpenAI

from app.config import get_settings

DEFAULT_BASE_MODEL = "gpt-4o-mini-2024-07-18"


def _client() -> OpenAI:
    settings = get_settings()
    if not settings.openai_api_key:
        sys.exit("OPENAI_API_KEY is not set.")
    return OpenAI(api_key=settings.openai_api_key)


def cmd_upload(args: argparse.Namespace) -> None:
    with open(args.path, "rb") as handle:
        uploaded = _client().files.create(file=handle, purpose="fine-tune")
    print(f"file id: {uploaded.id}  ({uploaded.bytes} bytes, {uploaded.filename})")


def cmd_create(args: argparse.Namespace) -> None:
    job = _client().fine_tuning.jobs.create(
        training_file=args.training_file,
        validation_file=args.val,
        model=args.base,
        suffix=args.suffix,
    )
    print(f"job id: {job.id}  status: {job.status}  base: {job.model}")
    print(f"track it: python -m scripts.finetune status {job.id}")


def cmd_status(args: argparse.Namespace) -> None:
    job = _client().fine_tuning.jobs.retrieve(args.job_id)
    print(f"status: {job.status}")
    if job.error and job.error.message:
        print(f"error: {job.error.message}")
    if job.fine_tuned_model:
        print(f"fine_tuned_model: {job.fine_tuned_model}")
        print("→ set OWL_FINE_TUNED_MODEL to that id, then OWL_FINE_TUNED_TRAFFIC=0.2")


def cmd_list(_args: argparse.Namespace) -> None:
    for job in _client().fine_tuning.jobs.list(limit=20).data:
        print(f"{job.id}  {job.status:<12}  {job.fine_tuned_model or '—'}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    up = sub.add_parser("upload", help="upload a JSONL training/validation file")
    up.add_argument("path")
    up.set_defaults(func=cmd_upload)

    cr = sub.add_parser("create", help="create a fine-tuning job")
    cr.add_argument("training_file", help="file id from `upload`")
    cr.add_argument("--val", help="validation file id (optional)")
    cr.add_argument("--base", default=DEFAULT_BASE_MODEL, help="base model to tune")
    cr.add_argument("--suffix", default="owl-sft", help="name suffix for the tuned model")
    cr.set_defaults(func=cmd_create)

    st = sub.add_parser("status", help="poll a job")
    st.add_argument("job_id")
    st.set_defaults(func=cmd_status)

    ls = sub.add_parser("list", help="recent jobs")
    ls.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
