INSERT INTO pgaudit.config (key, value) VALUES ('H', 'YYYY');

CREATE TABLE IF NOT EXISTS pgaudit.history (
    id            INTEGER,
    table_name    VARCHAR(250),
    register_date TIMESTAMP WITH TIME ZONE NOT NULL,
    user_db       TEXT NOT NULL,
    session_id        TEXT,
    command       CHAR(1) NOT NULL,
    old           JSON,
    new           JSON
) PARTITION BY RANGE (register_date);

CREATE OR REPLACE FUNCTION pgaudit.vacuum(now TIMESTAMP WITH TIME ZONE) RETURNS VARCHAR
LANGUAGE plpgsql AS $split_log_by_date$
DECLARE
    format VARCHAR;
    year INTEGER;
    query TEXT;
BEGIN
    SELECT value INTO format FROM pgaudit.config WHERE key = 'H' AND state = '1';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Format for history NOT configured';
    END IF;
    FOR year IN SELECT DISTINCT TO_CHAR(register_date, format) FROM pgaudit.log
    LOOP
        query := $SQL$
            CREATE TABLE IF NOT EXISTS log_TG_YEAR PARTITION OF pgaudit.history FOR VALUES FROM ('TG_YEAR-01-01') TO ('TG_NEXT_YEAR-01-01');
        $SQL$;
        query := REPLACE(query, 'TG_YEAR', year::VARCHAR);
        query := REPLACE(query, 'TG_NEXT_YEAR', (year + 1)::VARCHAR);
        EXECUTE query;
    END LOOP;
    INSERT INTO pgaudit.history(id, table_name, register_date, user_db, session_id, command, old, new)
    SELECT id, table_name, register_date, user_db, session_id, command, old, new FROM pgaudit.log
    WHERE register_date < now;
    DELETE FROM pgaudit.log WHERE register_date < now;
    RETURN 'History updated';
END
$split_log_by_date$;

CREATE OR REPLACE FUNCTION pgaudit.vacuum() RETURNS VARCHAR
LANGUAGE plpgsql AS $split_default_log_by_date$
BEGIN
    RETURN pgaudit.split(CURRENT_TIMESTAMP);
END
$split_default_log_by_date$;