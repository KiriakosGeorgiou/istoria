/*
 * Caller: history_replay() 
 *
 * Use Case: Deletes the record represented by p_jsonb from table p_table. 
 *
 * Description: The function identifies the primary key(s) in table p_table,
 *   and then uses the record information represented by p_jsonb to delete
 *   the record by the primary key(s).
 */

create or replace function history_delete(
    p_table text, p_jsonb jsonb
)
returns void
as $$ 
declare
    l_where_clause text;
begin
    -- find the PKs of p_table and build join clause for the delete
    execute
        format(
            $FMT$
            with
                tmp_pk as (
                    select a.attname as id
                    from pg_index i
                    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
                    where i.indrelid = %L::regclass
                    and i.indisprimary
                )
                select string_agg('%I.' || quote_ident(id) || '=tmp_del.' || quote_ident(id), ' and ')
                from tmp_pk
            $FMT$,
            p_table,
            p_table
        )
        into strict l_where_clause;

    execute
        format(
            $FMT$
            with
                tmp_del as ( -- helper to make the delete via a join easy
                    select * from jsonb_populate_record(null::%I, $1)
                )
                delete from %I using tmp_del
                where %s
            $FMT$,
            p_table,
            p_table, l_where_clause
        )
        using p_jsonb;
end;
$$ language plpgsql;
