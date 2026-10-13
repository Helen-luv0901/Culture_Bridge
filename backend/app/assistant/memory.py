"""Short-term conversation memory, keyed by owner so accounts never see each other's chats.

In-process only: conversations are not stored long-term (tech-architecture §4.8) and are lost on
restart. Swap for a shared store if the backend runs more than one instance.
"""

import threading
import time
from dataclasses import dataclass

from app.assistant.llm import Turn, UserTurn


@dataclass
class _Conversation:
    turns: list[Turn]
    touched_at: float


class ConversationStore:
    def __init__(
        self,
        max_exchanges: int = 6,
        ttl_seconds: float = 2 * 60 * 60,
        max_conversations: int = 5000,
    ) -> None:
        self._max_exchanges = max_exchanges
        self._ttl = ttl_seconds
        self._max_conversations = max_conversations
        self._items: dict[tuple[str, str], _Conversation] = {}
        self._lock = threading.Lock()

    def load(self, owner: str, conversation_id: str) -> list[Turn]:
        with self._lock:
            item = self._items.get((owner, conversation_id))
            if item is None or time.monotonic() - item.touched_at > self._ttl:
                return []
            return list(item.turns)

    def save(self, owner: str, conversation_id: str, turns: list[Turn]) -> None:
        with self._lock:
            self._items[(owner, conversation_id)] = _Conversation(
                turns=self._trim(turns), touched_at=time.monotonic()
            )
            self._evict()

    def clear(self, owner: str, conversation_id: str) -> None:
        with self._lock:
            self._items.pop((owner, conversation_id), None)

    def _trim(self, turns: list[Turn]) -> list[Turn]:
        """Keep the last N exchanges, cutting only at user messages so tool calls stay paired."""
        starts = [i for i, turn in enumerate(turns) if isinstance(turn, UserTurn)]
        if len(starts) <= self._max_exchanges:
            return list(turns)
        return list(turns[starts[-self._max_exchanges] :])

    def _evict(self) -> None:
        now = time.monotonic()
        for key in [k for k, v in self._items.items() if now - v.touched_at > self._ttl]:
            del self._items[key]
        while len(self._items) > self._max_conversations:
            oldest = min(self._items, key=lambda k: self._items[k].touched_at)
            del self._items[oldest]
