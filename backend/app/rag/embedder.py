"""Text embeddings for semantic search (Gemini; a deterministic fake for tests)."""

import hashlib
import logging
import math
from functools import lru_cache
from typing import Protocol

from google import genai
from google.genai import types

from app.core.config import get_settings
from app.models import EMBEDDING_DIMENSIONS

logger = logging.getLogger(__name__)


class EmbeddingUnavailable(Exception):
    pass


class Embedder(Protocol):
    def embed_documents(self, texts: list[str]) -> list[list[float]]: ...

    def embed_query(self, text: str) -> list[float]: ...


class GeminiEmbedder:
    def __init__(self, api_key: str, model: str, timeout_seconds: float) -> None:
        self._client = genai.Client(
            api_key=api_key, http_options=types.HttpOptions(timeout=int(timeout_seconds * 1000))
        )
        self._model = model

    def _embed(self, texts: list[str], task: str) -> list[list[float]]:
        try:
            response = self._client.models.embed_content(
                model=self._model,
                contents=texts,
                config=types.EmbedContentConfig(
                    task_type=task, output_dimensionality=EMBEDDING_DIMENSIONS
                ),
            )
        except Exception as exc:
            logger.warning("Embedding failed: %s", exc)
            raise EmbeddingUnavailable(str(exc)) from exc
        vectors = [e.values or [] for e in response.embeddings or []]
        if len(vectors) != len(texts) or any(len(v) != EMBEDDING_DIMENSIONS for v in vectors):
            raise EmbeddingUnavailable("unexpected embedding shape")
        return vectors

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        out: list[list[float]] = []
        for start in range(0, len(texts), 100):  # API batch limit
            out += self._embed(texts[start : start + 100], "RETRIEVAL_DOCUMENT")
        return out

    def embed_query(self, text: str) -> list[float]:
        return self._embed([text], "RETRIEVAL_QUERY")[0]


class HashingEmbedder:
    """Character-bigram hashing: texts sharing words land close together. Tests and offline dev."""

    def _vector(self, text: str) -> list[float]:
        vec = [0.0] * EMBEDDING_DIMENSIONS
        text = text.lower()
        grams = [text[i : i + 2] for i in range(len(text) - 1)] or [text]
        for gram in grams:
            if gram.strip():
                h = int(hashlib.md5(gram.encode()).hexdigest(), 16)
                vec[h % EMBEDDING_DIMENSIONS] += 1.0
        norm = math.sqrt(sum(v * v for v in vec)) or 1.0
        return [v / norm for v in vec]

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [self._vector(t) for t in texts]

    def embed_query(self, text: str) -> list[float]:
        return self._vector(text)


class UnavailableEmbedder:
    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        raise EmbeddingUnavailable("GEMINI_API_KEY is not configured")

    def embed_query(self, text: str) -> list[float]:
        raise EmbeddingUnavailable("GEMINI_API_KEY is not configured")


@lru_cache
def get_embedder() -> Embedder:
    settings = get_settings()
    if not settings.gemini_api_key:
        return UnavailableEmbedder()
    return GeminiEmbedder(
        settings.gemini_api_key, settings.embedding_model, settings.gemini_timeout_seconds
    )
