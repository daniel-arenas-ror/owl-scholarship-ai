"""Deterministic, dependency-free chunking. Good enough for scholarship pages
(a few paragraphs); revisit if a source turns out to need more nuance.
"""

TARGET_CHARS = 900
OVERLAP_CHARS = 150


def chunk_markdown(
    text: str, target_chars: int = TARGET_CHARS, overlap_chars: int = OVERLAP_CHARS
) -> list[str]:
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    if not paragraphs:
        return [text.strip()] if text.strip() else []

    chunks: list[str] = []
    current = ""
    for para in paragraphs:
        candidate = f"{current}\n\n{para}".strip() if current else para
        if not current or len(candidate) <= target_chars:
            current = candidate
            continue

        chunks.append(current)
        tail = current[-overlap_chars:] if overlap_chars else ""
        current = f"{tail}\n\n{para}".strip()

    if current:
        chunks.append(current)

    return chunks
