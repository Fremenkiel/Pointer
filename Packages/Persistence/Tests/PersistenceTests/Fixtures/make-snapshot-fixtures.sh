#!/bin/sh
# Makes the snapshot fixtures of the import checks from library-v1.sql (task 1.3 of
# docs/m9-plan.md, D-162). Run it in this folder: sh make-snapshot-fixtures.sh
set -e
rm -f snapshot-*.sqlite
sqlite3 snapshot-source.sqlite < library-v1.sql
# A good snapshot: VACUUM INTO, as SnapshotWriter makes it, in rollback mode.
sqlite3 snapshot-source.sqlite "VACUUM INTO 'snapshot-good.sqlite'"
rm snapshot-source.sqlite
# Another magic text in the first 16 bytes.
cp snapshot-good.sqlite snapshot-wrong-magic.sqlite
printf 'NotSQLite form 3' | dd of=snapshot-wrong-magic.sqlite bs=1 seek=0 conv=notrunc 2>/dev/null
# Page size 8192.
sed 's/page_size = 4096/page_size = 8192/' library-v1.sql | sqlite3 snapshot-page-8192.sqlite
# WAL mode: header bytes 18 and 19 are 2. The close of sqlite3 removes the -wal file.
cp snapshot-good.sqlite snapshot-wal.sqlite
sqlite3 snapshot-wal.sqlite "PRAGMA journal_mode = WAL" > /dev/null
# A newer schema version.
cp snapshot-good.sqlite snapshot-newer.sqlite
sqlite3 snapshot-newer.sqlite "PRAGMA user_version = 2"
# A damaged page: 8 bytes of 0xFF in the cells of page 11, the table stroke.
cp snapshot-good.sqlite snapshot-damaged.sqlite
printf '\377\377\377\377\377\377\377\377' |
    dd of=snapshot-damaged.sqlite bs=1 seek=$((10 * 4096 + 4000)) conv=notrunc 2>/dev/null
# A missing column: the table stroke without origin_y, and no stroke rows.
grep -v 'origin_y' library-v1.sql | grep -v '^INSERT INTO stroke' |
    sqlite3 snapshot-missing-column.sqlite
# An extra trigger.
cp snapshot-good.sqlite snapshot-trigger.sqlite
sqlite3 snapshot-trigger.sqlite \
    "CREATE TRIGGER wipe AFTER INSERT ON workspace BEGIN DELETE FROM card; END"
