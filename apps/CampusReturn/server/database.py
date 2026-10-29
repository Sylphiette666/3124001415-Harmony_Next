from contextlib import contextmanager
import json
from pathlib import Path
import sqlite3

SCHEMA = '''
CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,name TEXT NOT NULL,role TEXT NOT NULL,secret TEXT NOT NULL,credit INTEGER NOT NULL DEFAULT 100,false_claims INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS items(id TEXT PRIMARY KEY,owner TEXT NOT NULL,kind TEXT NOT NULL,data TEXT NOT NULL,digest TEXT NOT NULL,answer_hash TEXT NOT NULL DEFAULT '',state TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1);
CREATE TABLE IF NOT EXISTS matches(id TEXT PRIMARY KEY,lost TEXT NOT NULL,found TEXT NOT NULL,score REAL NOT NULL,state TEXT NOT NULL,created INTEGER NOT NULL,deadline INTEGER NOT NULL,winner TEXT,priority_user TEXT NOT NULL DEFAULT '',UNIQUE(lost,found));
CREATE TABLE IF NOT EXISTS claims(id TEXT PRIMARY KEY,match_id TEXT NOT NULL,found TEXT NOT NULL,user_id TEXT NOT NULL,state TEXT NOT NULL,created INTEGER NOT NULL,score REAL NOT NULL DEFAULT 0,level INTEGER NOT NULL DEFAULT 1,answer TEXT NOT NULL DEFAULT '',evidence TEXT NOT NULL DEFAULT '',image TEXT NOT NULL DEFAULT '',UNIQUE(found,user_id));
CREATE UNIQUE INDEX IF NOT EXISTS serial_verification ON claims(found) WHERE state='核验中';
CREATE TABLE IF NOT EXISTS appeals(id TEXT PRIMARY KEY,match_id TEXT NOT NULL,user_id TEXT NOT NULL,level INTEGER NOT NULL,evidence TEXT NOT NULL,image TEXT NOT NULL,state TEXT NOT NULL,created INTEGER NOT NULL,deadline INTEGER NOT NULL,decision TEXT NOT NULL DEFAULT '');
CREATE UNIQUE INDEX IF NOT EXISTS one_pending_appeal ON appeals(match_id) WHERE state='待裁定';
CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY AUTOINCREMENT,match_id TEXT NOT NULL,actor TEXT NOT NULL,state TEXT NOT NULL,message TEXT NOT NULL,created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS notifications(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id TEXT NOT NULL,message TEXT NOT NULL,created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS ledger(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id TEXT NOT NULL,kind TEXT NOT NULL,delta INTEGER NOT NULL,reason_id TEXT NOT NULL,actor TEXT NOT NULL,created INTEGER NOT NULL,UNIQUE(user_id,kind,reason_id));
CREATE TABLE IF NOT EXISTS changes(seq INTEGER PRIMARY KEY AUTOINCREMENT,item_id TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS config(key TEXT PRIMARY KEY,data TEXT NOT NULL);
'''


@contextmanager
def connect(path):
    db = sqlite3.connect(str(path), timeout=20)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys=ON')
    db.execute('PRAGMA journal_mode=WAL')
    try:
        db.executescript(SCHEMA)
        db.execute('BEGIN IMMEDIATE')
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
