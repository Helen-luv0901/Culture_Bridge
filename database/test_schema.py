"""Execute the draft in memory and verify its core integrity boundaries."""
import sqlite3
import unittest
from pathlib import Path

SCHEMA = Path(__file__).with_name('schema.sql')

class SchemaTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.executescript(SCHEMA.read_text(encoding='utf-8-sig'))
        self.db.executemany('INSERT INTO users(id,auth_subject,role) VALUES(?,?,?)',
                            [('author','auth-author','student'),('other','auth-other','student'),('reviewer','auth-reviewer','reviewer')])
        self.db.execute("INSERT INTO actions VALUES('permit','work-permit',NULL)")
        for version in ('v1','v2'):
            self.db.execute('INSERT INTO action_versions(id,action_id,version_number,title_zh,title_en,applicable_to,created_by) VALUES(?,?,?,?,?,?,?)',
                            (version,'permit',int(version[-1]),'工作證','Work permit','International students','reviewer'))
            self.db.execute('INSERT INTO action_steps VALUES(?,?,1,?,?,NULL)',('step-'+version,version,'準備文件','Prepare documents'))
        self.db.execute("INSERT INTO experiences(id,author_id,topic_id,identity_type,original_voice) VALUES('e1','author','culture_communication','degree_student','My original voice')")
        self.db.execute("INSERT INTO experience_summaries(id,experience_id,version_number,source_voice,situation,feeling_or_attempt,reminder,model_name) VALUES('s1','e1',1,'My original voice','Situation','Feeling','Reminder','test-model')")
        self.db.commit()

    def tearDown(self):
        self.db.close()

    def test_publication_requires_current_voice_author_confirmation(self):
        publish = "UPDATE experiences SET status='published',confirmed_summary_id='s1',published_at='2026-10-10T00:00:00.000Z' WHERE id='e1'"
        with self.assertRaises(sqlite3.IntegrityError): self.db.execute(publish)
        self.db.execute("UPDATE experience_summaries SET confirmed_by='other',confirmed_at='2026-10-10T00:00:00.000Z' WHERE id='s1'")
        with self.assertRaises(sqlite3.IntegrityError): self.db.execute(publish)
        self.db.execute("UPDATE experience_summaries SET confirmed_by='author' WHERE id='s1'")
        self.db.execute(publish)
        self.assertEqual(self.db.execute('SELECT count(*) FROM public_experiences').fetchone()[0],1)
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE experiences SET original_voice='Changed' WHERE id='e1'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE experience_summaries SET situation='Changed' WHERE id='s1'")
        self.db.commit()
        self.assertFalse(self.db.execute('PRAGMA foreign_key_check').fetchall())

    def test_verification_requires_reviewer_and_source(self):
        verify = "UPDATE action_versions SET verification_status='verified' WHERE id='v1'"
        with self.assertRaises(sqlite3.IntegrityError): self.db.execute(verify)
        self.db.execute("INSERT INTO sources VALUES('source','Official document','https://example.org/document','Example institution','official','2026-10-10T00:00:00.000Z')")
        self.db.execute("INSERT INTO action_version_sources VALUES('v1','source','Check required documents')")
        self.db.execute("INSERT INTO verification_records(id,action_version_id,source_id,reviewer_id,decision,note) VALUES('review','v1','source','reviewer','verified','Reviewed source')")
        self.db.execute(verify)
        self.assertEqual(self.db.execute("SELECT verification_status FROM action_versions WHERE id='v1'").fetchone()[0],'verified')

    def test_execution_pins_steps_to_its_version(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO executions(id,user_id,action_version_id,identity_type) VALUES('attempt','author','v1','degree_student')")
        self.db.execute("UPDATE action_versions SET published_at='2026-10-10T00:00:00.000Z' WHERE id='v1'")
        self.db.execute("INSERT INTO executions(id,user_id,action_version_id,identity_type) VALUES('attempt','author','v1','degree_student')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO execution_steps(execution_id,action_version_id,step_id,state) VALUES('attempt','v1','step-v2','done')")
        self.db.execute("INSERT INTO execution_steps(execution_id,action_version_id,step_id,state) VALUES('attempt','v1','step-v1','done')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE action_steps SET title_en='Changed' WHERE id='step-v1'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE action_versions SET title_en='Changed' WHERE id='v1'")
        self.db.commit()
        self.assertFalse(self.db.execute('PRAGMA foreign_key_check').fetchall())

    def test_reactions_are_unique_and_views_hide_drafts(self):
        self.assertEqual(self.db.execute('SELECT count(*) FROM public_experiences').fetchone()[0],0)
        self.db.execute("INSERT INTO experience_reactions(experience_id,user_id,kind) VALUES('e1','other','helpful')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO experience_reactions(experience_id,user_id,kind) VALUES('e1','other','helpful')")

if __name__ == '__main__':
    unittest.main(verbosity=2)
