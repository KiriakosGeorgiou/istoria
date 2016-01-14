/*
 * Caller: history_replay() 
 *
 * Use Case: Inserts the record represented by p_jsonb to table p_table. 
 *
 * Description: This is how insert actions are replayed back into the
 *   session table.
 */

create or replace function history_insert(
    p_table text, p_jsonb jsonb
)
returns void
as $$ 
begin

    execute format('insert into %I select * from jsonb_populate_record(null::%I, $1)', p_table, p_table)
    using p_jsonb;

end;
$$ language plpgsql;
