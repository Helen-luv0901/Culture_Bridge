"""Retrieval quality check for semantic search (A-24).

    uv run python -m app.rag.evaluate                     # Gemini embeddings (GEMINI_API_KEY)
    uv run python -m app.rag.evaluate --fake              # offline smoke run
    uv run python -m app.rag.evaluate --reindex cases.json

Each case is {"query": ..., "expect": ["experience:<id>" | "feedback:<id>" | "doc:<title>"]}.
Reports hit@k and MRR, plus the distances of expected vs other results, which is what
SEMANTIC_MAX_DISTANCE should sit between.
"""

import argparse
import json
import statistics
from dataclasses import dataclass, field
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.db import get_sessionmaker
from app.models import ContentEmbedding, Experience, KbChunk, KbDocument
from app.rag.embedder import Embedder, HashingEmbedder, get_embedder
from app.rag.index import sync_experience

DEFAULT_CASES = Path(__file__).with_name("eval_cases.json")


@dataclass
class Report:
    cases: int = 0
    hits: int = 0
    reciprocal_ranks: list[float] = field(default_factory=list)
    expected_distances: list[float] = field(default_factory=list)
    other_distances: list[float] = field(default_factory=list)
    misses: list[str] = field(default_factory=list)

    @property
    def mrr(self) -> float:
        return statistics.fmean(self.reciprocal_ranks) if self.reciprocal_ranks else 0.0


def ranked(db: Session, embedder: Embedder, query: str, k: int) -> list[tuple[str, float]]:
    """Top-k keys and cosine distances across documents and user content, without cut-off."""
    vector = embedder.embed_query(query)
    doc_d = KbChunk.embedding.cosine_distance(vector)
    docs = db.execute(
        select(KbDocument.title, doc_d)
        .join(KbDocument, KbDocument.id == KbChunk.document_id)
        .where(KbDocument.active.is_(True))
        .order_by(doc_d)
        .limit(k)
    ).all()
    content_d = ContentEmbedding.embedding.cosine_distance(vector)
    content = db.execute(
        select(ContentEmbedding.content_type, ContentEmbedding.content_id, content_d)
        .order_by(content_d)
        .limit(k)
    ).all()
    keys = [(f"doc:{title}", d) for title, d in docs]
    keys += [
        (f"{'feedback' if t == 'execution_feedback' else t}:{cid}", d) for t, cid, d in content
    ]
    return sorted(keys, key=lambda kd: kd[1])[:k]


def evaluate(db: Session, embedder: Embedder, cases: list[dict], k: int = 5) -> Report:
    report = Report()
    for case in cases:
        expected = set(case["expect"])
        results = ranked(db, embedder, case["query"], k)
        report.cases += 1
        rank = next((i for i, (key, _) in enumerate(results, 1) if key in expected), None)
        if rank:
            report.hits += 1
            report.reciprocal_ranks.append(1 / rank)
        else:
            report.reciprocal_ranks.append(0.0)
            report.misses.append(case["query"])
        for key, distance in results:
            target = report.expected_distances if key in expected else report.other_distances
            target.append(distance)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("cases", nargs="?", default=str(DEFAULT_CASES))
    parser.add_argument("-k", type=int, default=5)
    parser.add_argument("--fake", action="store_true", help="offline hashing embedder")
    parser.add_argument("--reindex", action="store_true", help="re-embed published experiences")
    args = parser.parse_args()
    embedder: Embedder = HashingEmbedder() if args.fake else get_embedder()
    cases = json.loads(Path(args.cases).read_text(encoding="utf-8"))
    with get_sessionmaker()() as db:
        if args.reindex:
            for eid in db.scalars(select(Experience.id).where(Experience.status == "published")):
                sync_experience(db, embedder, eid)
        r = evaluate(db, embedder, cases, args.k)
    print(f"cases {r.cases}  hit@{args.k} {r.hits / max(r.cases, 1):.0%}  MRR {r.mrr:.2f}")
    for name, values in (("expected", r.expected_distances), ("other", r.other_distances)):
        if values:
            print(
                f"{name:9} distance  min {min(values):.3f}  median {statistics.median(values):.3f}"
                f"  max {max(values):.3f}"
            )
    for query in r.misses:
        print(f"MISS  {query}")


if __name__ == "__main__":
    main()
