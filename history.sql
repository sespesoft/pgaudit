CREATE TABLE IF NOT EXISTS pgaudit.history (
    id            INTEGER,
    audit_object  VARCHAR(4000) NOT NULL,
    register_date TIMESTAMP WITH TIME ZONE NOT NULL,
    user_db       VARCHAR(63) NOT NULL,
    session_id    VARCHAR(40),
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
    SELECT value INTO format FROM pgaudit.config WHERE key = 'H';
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
    INSERT INTO pgaudit.history(id, audit_object, register_date, user_db, session_id, command, old, new)
    SELECT id, audit_object, register_date, user_db, session_id, command, old, new FROM pgaudit.log
    WHERE register_date < now;
    DELETE FROM pgaudit.log WHERE register_date < now;
    RETURN 'History updated';
END
$split_log_by_date$;

CREATE OR REPLACE FUNCTION pgaudit.vacuum() RETURNS VARCHAR
LANGUAGE plpgsql AS $split_default_log_by_date$
BEGIN
    RETURN pgaudit.vacuum(CURRENT_TIMESTAMP);
END
$split_default_log_by_date$;