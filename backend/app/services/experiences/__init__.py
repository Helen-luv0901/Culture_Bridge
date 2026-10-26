"""Student experiences (B-8..B-16).

Posts (the redesign): the author writes a title and text, picks a category and tags, and the
post is published exactly as written; the AI only suggests tags. Each post still gets a confirmed
"verbatim" summary (empty parts) so the database's publication gate stays the same.

Older flow (kept for existing drafts): draft -> AI summary -> author confirms -> published.
Either way posts are translated in the background and never carry a verification status. Public
payloads never expose the author's account; they show a name only when the author chose to sign
with their nickname or real name, read live from the account.

The package is split by job: schemas, public reads (queries), authoring (posts), reactions and
saved items, and translations. Everything callers use is re-exported here.
"""

from app.services.experiences.posts import (
    MAX_POSTS_PER_DAY,
    create_draft,
    create_post,
    delete_experience,
    delete_experiences,
    generate_summary,
    get_mine,
    my_experience,
    my_experiences,
    popular_tags,
    publish,
    update_draft,
)
from app.services.experiences.queries import SEARCH_CANDIDATES, explore, get_public, search
from app.services.experiences.reactions import (
    MAX_SAVED,
    saved_experiences,
    set_reaction,
    set_saved,
)
from app.services.experiences.schemas import (
    MAX_TAG_LENGTH,
    MAX_TAGS,
    MAX_TITLE,
    MAX_VOICE,
    VERBATIM,
    AuthorDisplay,
    Category,
    DraftIn,
    DraftUpdate,
    ExperienceDetail,
    ExperiencePage,
    IdentityType,
    Impact,
    Locale,
    MyExperience,
    PostIn,
    PublicExperience,
    PublishIn,
    ReactionKind,
    Sort,
    SummaryOut,
    TopicId,
    TranslationOut,
    clean_tags,
    topic_for,
)
from app.services.experiences.translations import translate, translate_in_background

__all__ = [
    "MAX_POSTS_PER_DAY",
    "MAX_SAVED",
    "MAX_TAGS",
    "MAX_TAG_LENGTH",
    "MAX_TITLE",
    "MAX_VOICE",
    "SEARCH_CANDIDATES",
    "VERBATIM",
    "AuthorDisplay",
    "Category",
    "DraftIn",
    "DraftUpdate",
    "ExperienceDetail",
    "ExperiencePage",
    "IdentityType",
    "Impact",
    "Locale",
    "MyExperience",
    "PostIn",
    "PublicExperience",
    "PublishIn",
    "ReactionKind",
    "Sort",
    "SummaryOut",
    "TopicId",
    "TranslationOut",
    "clean_tags",
    "create_draft",
    "create_post",
    "delete_experience",
    "delete_experiences",
    "explore",
    "generate_summary",
    "get_mine",
    "get_public",
    "my_experience",
    "my_experiences",
    "popular_tags",
    "publish",
    "saved_experiences",
    "search",
    "set_reaction",
    "set_saved",
    "topic_for",
    "translate",
    "translate_in_background",
    "update_draft",
]
