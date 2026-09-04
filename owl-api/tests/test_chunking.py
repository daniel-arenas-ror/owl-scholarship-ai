from app.chunking import chunk_markdown


def test_short_text_is_a_single_chunk():
    text = "Beca para maestría.\n\nAplica a estudiantes de ingeniería."
    assert chunk_markdown(text, target_chars=1000) == [text]


def test_long_text_splits_into_multiple_chunks():
    paragraphs = [f"Detalle {i}: " + ("relevante " * 8) for i in range(8)]
    text = "\n\n".join(paragraphs)

    chunks = chunk_markdown(text, target_chars=120, overlap_chars=20)

    assert len(chunks) > 1
    for i in range(8):
        assert any(f"Detalle {i}:" in chunk for chunk in chunks)


def test_blank_text_returns_no_chunks():
    assert chunk_markdown("   ") == []
