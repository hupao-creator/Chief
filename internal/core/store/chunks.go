package store

import (
	"bytes"
	"encoding/json"
	"fmt"
	"unicode/utf8"
)

// Leave space for the key and cell header on a typical 8 KiB leaf page.
// A short final part (empty for an exact multiple) detects incomplete tails.
const chunkBytes = 7680
const inlineLimit = 64 << 10

var chunkSchema = fmt.Sprintf("CREATE TABLE record_chunks (key TEXT NOT NULL, part INTEGER NOT NULL CHECK(part>=0), body BLOB NOT NULL CHECK(length(body)<=%d), PRIMARY KEY(key,part)) STRICT", chunkBytes)

func (d *database) readChunks(data *snapshotData) error {
	s, err := d.prepare("SELECT key,part,length(body),body FROM record_chunks ORDER BY key,part")
	if err != nil {
		return err
	}
	defer s.Close()
	var currentKey string
	var body []byte
	for {
		row, err := s.Step()
		if err != nil {
			return err
		}
		if !row {
			if len(body) != 0 {
				return ErrInvalidState
			}
			return nil
		}
		key := s.Text(0)
		if len(body) == 0 {
			if validKey(key) != nil {
				return ErrInvalidState
			}
			if _, exists := indexGet(data.records, key); exists {
				return ErrInvalidState
			}
			currentKey = key
		}
		size := s.Integer(2)
		if key != currentKey || s.Integer(1) != int64(len(body)/chunkBytes) || size < 0 || size > chunkBytes {
			return ErrInvalidState
		}
		if size > int64(MaxRecordBytes-len(body)) {
			return ErrRecordTooLarge
		}
		body = append(body, s.Blob(3)...)
		if size == chunkBytes {
			continue
		}
		if !utf8.Valid(body) || !json.Valid(body) {
			return ErrInvalidState
		}
		value := newStoredRecord(body, true)
		data.records = indexSet(data.records, key, value)
		data.lifecycle.update(key, value)
		body = body[:0]
	}
}

func (d *database) writeRecord(key string, old, next *storedRecord) error {
	if old != nil && (next == nil || old.chunked != next.chunked) {
		remove := "DELETE FROM records WHERE key=?"
		if old.chunked {
			remove = "DELETE FROM record_chunks WHERE key=?"
		}
		if err := d.run(remove, key); err != nil {
			return err
		}
	}
	if next == nil {
		return nil
	}
	if !next.chunked {
		return d.run("INSERT INTO records(key,body) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET body=excluded.body", key, []byte(next.body))
	}
	var previous []byte
	if old != nil && old.chunked {
		previous = old.body
	}
	return d.writeChunks(key, previous, next.body)
}

func (d *database) writeChunks(key string, old, next []byte) error {
	for offset := 0; offset <= len(next); offset += chunkBytes {
		chunk := next[offset:min(offset+chunkBytes, len(next))]
		if old != nil && offset <= len(old) && bytes.Equal(chunk, old[offset:min(offset+chunkBytes, len(old))]) {
			continue
		}
		if err := d.run("INSERT INTO record_chunks(key,part,body) VALUES (?,?,?) ON CONFLICT(key,part) DO UPDATE SET body=excluded.body", key, offset/chunkBytes, chunk); err != nil {
			return err
		}
	}
	if len(old)/chunkBytes > len(next)/chunkBytes {
		return d.run("DELETE FROM record_chunks WHERE key=? AND part>?", key, len(next)/chunkBytes)
	}
	return nil
}
