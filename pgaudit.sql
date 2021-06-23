CREATE SCHEMA IF NOT EXISTS pgaudit;

CREATE TABLE IF NOT EXISTS pgaudit.config(
    key char(1) NOT NULL PRIMARY KEY,
    value varchar(20) NOT NULL,
    state bit(1) NOT NULL DEFAULT '1'
);

CREATE TABLE IF NOT EXISTS pgaudit.log(
    id            SERIAL NOT NULL PRIMARY KEY,
    table_name    VARCHAR(250),
    register_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT current_timestamp,
    user_db       TEXT NOT NULL DEFAULT USER,
    session_id        TEXT,
    command       CHAR(1) NOT NULL REFERENCES pgaudit.config(key),
    old           JSON,
    new           JSON
);

CREATE OR REPLACE FUNCTION pgaudit.track() RETURNS TRIGGER STRICT LANGUAGE plpgsql
AS $audit_table$
DECLARE
    session_id TEXT;
    table_name TEXT;
    config RECORD;
BEGIN
table_name := TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME;
    PERFORM relname
    FROM pg_class
    WHERE relname = 'tbl_session'
    AND CASE WHEN has_schema_privilege(relnamespace, 'USAGE')
        THEN pg_table_is_visible(oid) ELSE false END;
    IF not found THEN
        session_id := NULL;
    ELSE
        session_id := (SELECT value FROM tbl_session WHERE name = 'session_id');
    END IF;

    SELECT * INTO config FROM pgaudit.config WHERE value = TG_OP AND state = '1';
    IF FOUND THEN
        IF TG_OP = 'INSERT' THEN
            INSERT INTO pgaudit.log(session_id, table_name, command, new) VALUES (session_id,  table_name, config.key, row_to_json(NEW));
        ELSIF TG_OP = 'DELETE' THEN
            INSERT INTO pgaudit.log(session_id, table_name, command, old) VALUES (session_id, table_name, config.key, row_to_json(OLD));
        ELSIF TG_OP = 'UPDATE' THEN
            INSERT INTO pgaudit.log(session_id, table_name, command, old, new) VALUES (session_id, table_name, config.key, row_to_json(OLD), row_to_json(NEW));
        END IF;
    END IF;
    RETURN NULL;
END
$audit_table$;

CREATE OR REPLACE FUNCTION pgaudit.unfollow(schema name, table_name name) RETURNS VARCHAR
LANGUAGE plpgsql AS $unfollow_table$
DECLARE
    table_origin TEXT;
BEGIN
    table_origin := schema || '.' || table_name;
    EXECUTE 'DROP TRIGGER IF EXISTS audit ON ' || table_origin';
    DROP FUNCTION IF EXIST pgaudit.track();';
    RETURN table_origin || ' table ending auditing...';
END
$unfollow_table$;

CREATE OR REPLACE FUNCTION pgaudit.follow(schema name, table_name name) RETURNS VARCHAR
LANGUAGE plpgsql AS $follow_table$
DECLARE
    table_origin TEXT;
BEGIN
    table_origin := schema || '.' || table_name;
    EXECUTE 'DROP TRIGGER IF EXISTS audit ON ' || table_origin || ';CREATE TRIGGER audit ' ||
        ' AFTER INSERT OR UPDATE OR DELETE ON ' || table_origin ||
        ' FOR EACH ROW EXECUTE PROCEDURE pgaudit.track();';

    RETURN table_origin || ' table being audited...';
END
$follow_table$;

CREATE OR REPLACE FUNCTION pgaudit.follow(table_name name) RETURNS VARCHAR
LANGUAGE plpgsql AS $follow_table_whithout_schema$
BEGIN
    RETURN pgaudit.follow('public', table_name);
END
$follow_table_whithout_schema$;

CREATE OR REPLACE FUNCTION pgaudit.unfollow(table_name name) RETURNS VARCHAR
LANGUAGE plpgsql AS $unfollow_table_whithout_schema$
BEGIN
    RETURN pgaudit.unfollow('public', table_name);
END
$unfollow_table_whithout_schema$;