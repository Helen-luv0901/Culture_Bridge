-- Culture Bridge schema, PostgreSQL version.
-- Converted from GitHub database/schema.sql (SQLite draft). Same tables, constraints and rules;
-- SQLite-only syntax replaced: PRAGMA removed, strftime() -> now()/TIMESTAMPTZ,
-- SQLite triggers -> PL/pgSQL trigger functions.
-- Run once on an empty database (AWS RDS for PostgreSQL 16, via pgAdmin or psql).

BEGIN;

CREATE TABLE users (
  id TEXT PRIMARY KEY NOT NULL,
  auth_subject TEXT NOT NULL UNIQUE,
  preferred_locale TEXT NOT NULL DEFAULT 'zh-Hant' CHECK (preferred_locale IN ('zh-Hant','en')),
  role TEXT NOT NULL DEFAULT 'student' CHECK (role IN ('student','reviewer','admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE institutions (
  id TEXT PRIMARY KEY NOT NULL,
  name_zh TEXT NOT NULL,
  name_en TEXT NOT NULL,
  city TEXT
);
CREATE TABLE topics (
  id TEXT PRIMARY KEY NOT NULL,
  name_zh TEXT NOT NULL,
  name_en TEXT NOT NULL
);
INSERT INTO topics VALUES
 ('life_adaptation','生活適應','Life adaptation'),
 ('culture_communication','文化與溝通','Culture & communication');

-- PROCEDURES: identity of a task is separate from its historical versions.
CREATE TABLE actions (
  id TEXT PRIMARY KEY NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  archived_at TIMESTAMPTZ
);
CREATE TABLE action_versions (
  id TEXT PRIMARY KEY NOT NULL,
  action_id TEXT NOT NULL REFERENCES actions(id),
  version_number INTEGER NOT NULL CHECK (version_number > 0),
  title_zh TEXT NOT NULL,
  title_en TEXT NOT NULL,
  description_zh TEXT NOT NULL DEFAULT '',
  description_en TEXT NOT NULL DEFAULT '',
  institution_id TEXT REFERENCES institutions(id),
  location TEXT,
  applicable_to TEXT NOT NULL,
  verification_status TEXT NOT NULL DEFAULT 'unverified'
    CHECK (verification_status IN ('unverified','community_supported','needs_review','verified','outdated')),
  published_at TIMESTAMPTZ,
  created_by TEXT NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (action_id, version_number)
);
CREATE TABLE action_steps (
  id TEXT PRIMARY KEY NOT NULL,
  action_version_id TEXT NOT NULL REFERENCES action_versions(id),
  position INTEGER NOT NULL CHECK (position > 0),
  title_zh TEXT NOT NULL,
  title_en TEXT NOT NULL,
  notes TEXT,
  UNIQUE (action_version_id, position),
  UNIQUE (action_version_id, id)
);
CREATE TABLE sources (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  publisher TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('official','institution','partner')),
  accessed_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE action_version_sources (
  action_version_id TEXT NOT NULL REFERENCES action_versions(id),
  source_id TEXT NOT NULL REFERENCES sources(id),
  evidence_note TEXT NOT NULL,
  PRIMARY KEY (action_version_id, source_id)
);
CREATE TABLE verification_records (
  id TEXT PRIMARY KEY NOT NULL,
  action_version_id TEXT NOT NULL REFERENCES action_versions(id),
  source_id TEXT NOT NULL,
  reviewer_id TEXT NOT NULL REFERENCES users(id),
  decision TEXT NOT NULL CHECK (decision IN ('verified','needs_review','outdated')),
  note TEXT NOT NULL,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (action_version_id, source_id)
    REFERENCES action_version_sources(action_version_id, source_id)
);

-- Each attempt pins the version the student actually saw, even after updates.
CREATE TABLE executions (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id),
  action_version_id TEXT NOT NULL REFERENCES action_versions(id),
  institution_id TEXT REFERENCES institutions(id),
  identity_type TEXT NOT NULL CHECK (identity_type IN ('degree_student','exchange_student','language_student','other')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  outcome TEXT CHECK (outcome IN ('success','failed','different','abandoned')),
  CHECK ((outcome IS NULL AND finished_at IS NULL) OR (outcome IS NOT NULL AND finished_at IS NOT NULL)),
  CHECK (finished_at IS NULL OR finished_at >= started_at),
  UNIQUE (id, action_version_id)
);
CREATE TABLE execution_steps (
  execution_id TEXT NOT NULL,
  action_version_id TEXT NOT NULL,
  step_id TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','done','stuck')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (execution_id, step_id),
  FOREIGN KEY (execution_id, action_version_id) REFERENCES executions(id, action_version_id),
  FOREIGN KEY (action_version_id, step_id) REFERENCES action_steps(action_version_id, id)
);
CREATE TABLE execution_feedback (
  id TEXT PRIMARY KEY NOT NULL,
  execution_id TEXT NOT NULL,
  action_version_id TEXT NOT NULL,
  step_id TEXT,
  kind TEXT NOT NULL CHECK (kind IN ('stuck','different','possibly_outdated')),
  category TEXT CHECK (category IN ('documents','fee','location','process','eligibility','website','other')),
  original_voice TEXT,
  review_state TEXT NOT NULL DEFAULT 'pending' CHECK (review_state IN ('pending','reviewed','dismissed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (execution_id, action_version_id) REFERENCES executions(id, action_version_id),
  FOREIGN KEY (action_version_id, step_id) REFERENCES action_steps(action_version_id, id),
  CHECK (kind <> 'stuck' OR step_id IS NOT NULL)
);

-- EXPERIENCES: never carry a factual verification/truth score.
CREATE TABLE experiences (
  id TEXT PRIMARY KEY NOT NULL,
  author_id TEXT NOT NULL REFERENCES users(id),
  topic_id TEXT NOT NULL REFERENCES topics(id),
  identity_type TEXT NOT NULL CHECK (identity_type IN ('degree_student','exchange_student','language_student','other')),
  original_voice TEXT NOT NULL CHECK (char_length(btrim(original_voice)) BETWEEN 1 AND 2000),
  source_locale TEXT NOT NULL DEFAULT 'zh-Hant' CHECK (source_locale IN ('zh-Hant','en')),
  institution_id TEXT REFERENCES institutions(id),
  location TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','hidden')),
  confirmed_summary_id TEXT,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (status <> 'published' OR (confirmed_summary_id IS NOT NULL AND published_at IS NOT NULL))
);
CREATE TABLE experience_summaries (
  id TEXT PRIMARY KEY NOT NULL,
  experience_id TEXT NOT NULL REFERENCES experiences(id),
  version_number INTEGER NOT NULL CHECK (version_number > 0),
  source_voice TEXT NOT NULL,
  situation TEXT NOT NULL,
  feeling_or_attempt TEXT NOT NULL,
  reminder TEXT NOT NULL,
  model_name TEXT NOT NULL,
  confirmed_by TEXT REFERENCES users(id),
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((confirmed_by IS NULL AND confirmed_at IS NULL) OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)),
  UNIQUE (experience_id, version_number),
  UNIQUE (experience_id, id)
);
-- experiences <-> experience_summaries reference each other, so this key is added after both tables exist.
ALTER TABLE experiences
  ADD CONSTRAINT experiences_confirmed_summary_fk
  FOREIGN KEY (id, confirmed_summary_id) REFERENCES experience_summaries(experience_id, id)
  DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE experience_translations (
  experience_id TEXT NOT NULL REFERENCES experiences(id),
  summary_id TEXT NOT NULL,
  locale TEXT NOT NULL CHECK (locale IN ('zh-Hant','en')),
  original_voice TEXT NOT NULL,
  situation TEXT NOT NULL,
  feeling_or_attempt TEXT NOT NULL,
  reminder TEXT NOT NULL,
  method TEXT NOT NULL CHECK (method IN ('human','ai')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (experience_id, summary_id, locale),
  FOREIGN KEY (experience_id, summary_id) REFERENCES experience_summaries(experience_id, id)
);
CREATE TABLE experience_reactions (
  experience_id TEXT NOT NULL REFERENCES experiences(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  kind TEXT NOT NULL CHECK (kind IN ('helpful','experienced_too')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (experience_id, user_id, kind)
);
-- A different experience is a full authored story, not just another like.
CREATE TABLE experience_links (
  from_experience_id TEXT NOT NULL REFERENCES experiences(id),
  to_experience_id TEXT NOT NULL REFERENCES experiences(id),
  kind TEXT NOT NULL CHECK (kind IN ('similar','different')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (from_experience_id, to_experience_id, kind),
  CHECK (from_experience_id <> to_experience_id)
);
CREATE TABLE action_experience_links (
  action_id TEXT NOT NULL REFERENCES actions(id),
  experience_id TEXT NOT NULL REFERENCES experiences(id),
  PRIMARY KEY (action_id, experience_id)
);

-- Publication gate: confirmation must be by the author and for this exact voice.
CREATE FUNCTION validate_experience_publication() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM experience_summaries s
    WHERE s.id = NEW.confirmed_summary_id AND s.experience_id = NEW.id
      AND s.confirmed_by = NEW.author_id AND s.confirmed_at IS NOT NULL
      AND s.source_voice = NEW.original_voice
  ) THEN
    RAISE EXCEPTION 'Author must confirm a summary of the current original voice';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER validate_experience_publication
  BEFORE INSERT OR UPDATE ON experiences
  FOR EACH ROW WHEN (NEW.status = 'published')
  EXECUTE FUNCTION validate_experience_publication();

CREATE FUNCTION protect_published_summary() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM experiences e WHERE e.status = 'published' AND e.confirmed_summary_id = OLD.id) THEN
    RAISE EXCEPTION 'Create a new summary version rather than edit a published summary';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER protect_published_summary
  BEFORE UPDATE ON experience_summaries
  FOR EACH ROW EXECUTE FUNCTION protect_published_summary();

-- Verification requires reviewer evidence.
CREATE FUNCTION reject_verified_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Create version and source evidence before marking it verified';
END $$;
CREATE TRIGGER validate_verification_insert
  BEFORE INSERT ON action_versions
  FOR EACH ROW WHEN (NEW.verification_status = 'verified')
  EXECUTE FUNCTION reject_verified_insert();

CREATE FUNCTION validate_verification_update() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM verification_records v JOIN users u ON u.id = v.reviewer_id
    WHERE v.action_version_id = NEW.id AND u.role IN ('reviewer','admin') AND v.decision = 'verified'
  ) THEN
    RAISE EXCEPTION 'Verification requires reviewer evidence';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER validate_verification_update
  BEFORE UPDATE OF verification_status ON action_versions
  FOR EACH ROW WHEN (NEW.verification_status = 'verified')
  EXECUTE FUNCTION validate_verification_update();

-- Published procedure content is versioned rather than rewritten in place.
CREATE FUNCTION reject_published_version_edit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Published procedure content requires a new version';
END $$;
CREATE TRIGGER freeze_version_content
  BEFORE UPDATE ON action_versions
  FOR EACH ROW WHEN (OLD.published_at IS NOT NULL AND (
    NEW.action_id IS DISTINCT FROM OLD.action_id OR NEW.version_number IS DISTINCT FROM OLD.version_number OR
    NEW.title_zh IS DISTINCT FROM OLD.title_zh OR NEW.title_en IS DISTINCT FROM OLD.title_en OR
    NEW.description_zh IS DISTINCT FROM OLD.description_zh OR NEW.description_en IS DISTINCT FROM OLD.description_en OR
    NEW.applicable_to IS DISTINCT FROM OLD.applicable_to OR NEW.institution_id IS DISTINCT FROM OLD.institution_id OR
    NEW.location IS DISTINCT FROM OLD.location OR NEW.published_at IS DISTINCT FROM OLD.published_at))
  EXECUTE FUNCTION reject_published_version_edit();

CREATE FUNCTION freeze_published_steps() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (TG_OP IN ('INSERT','UPDATE') AND EXISTS (
        SELECT 1 FROM action_versions WHERE id = NEW.action_version_id AND published_at IS NOT NULL))
     OR (TG_OP IN ('UPDATE','DELETE') AND EXISTS (
        SELECT 1 FROM action_versions WHERE id = OLD.action_version_id AND published_at IS NOT NULL)) THEN
    RAISE EXCEPTION 'Published steps require a new action version';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER freeze_steps
  BEFORE INSERT OR UPDATE OR DELETE ON action_steps
  FOR EACH ROW EXECUTE FUNCTION freeze_published_steps();

CREATE FUNCTION validate_execution_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM action_versions WHERE id = NEW.action_version_id AND published_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Students can only start published procedure versions';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER validate_execution_version
  BEFORE INSERT ON executions
  FOR EACH ROW EXECUTE FUNCTION validate_execution_version();

CREATE INDEX idx_action_versions_published ON action_versions(action_id, published_at, version_number);
CREATE INDEX idx_executions_recent ON executions(action_version_id, finished_at, outcome);
CREATE INDEX idx_executions_user ON executions(user_id, started_at);
CREATE INDEX idx_feedback_step ON execution_feedback(action_version_id, step_id, kind, created_at);
CREATE INDEX idx_experiences_explore ON experiences(status, topic_id, identity_type, published_at);
CREATE INDEX idx_experiences_author ON experiences(author_id, status);
CREATE INDEX idx_links_reverse ON experience_links(to_experience_id, kind);
CREATE INDEX idx_reactions_user ON experience_reactions(user_id, kind);
CREATE INDEX idx_verifications_version ON verification_records(action_version_id, checked_at);

-- Public projection intentionally excludes author_id and optional identifying context.
CREATE VIEW public_experiences AS
 SELECT e.id, e.topic_id, e.identity_type, e.original_voice, e.source_locale, e.published_at,
        s.id AS summary_id, s.situation, s.feeling_or_attempt, s.reminder, s.confirmed_at,
        (SELECT count(*) FROM experience_reactions r WHERE r.experience_id = e.id AND r.kind = 'helpful') AS helpful_count,
        (SELECT count(*) FROM experience_links l JOIN experiences other ON other.id = l.to_experience_id
          WHERE l.from_experience_id = e.id AND l.kind = 'different' AND other.status = 'published') AS different_count
 FROM experiences e JOIN experience_summaries s ON s.id = e.confirmed_summary_id AND s.experience_id = e.id
 WHERE e.status = 'published';

CREATE VIEW latest_published_actions AS
 SELECT v.* FROM action_versions v
 WHERE v.published_at IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM action_versions newer WHERE newer.action_id = v.action_id
   AND newer.published_at IS NOT NULL AND newer.version_number > v.version_number
 ) AND EXISTS (SELECT 1 FROM actions a WHERE a.id = v.action_id AND a.archived_at IS NULL);

COMMIT;
