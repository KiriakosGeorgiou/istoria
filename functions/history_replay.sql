/*
 * Caller: history_sessions_trigger_func()    
 *
 * Use Case: This function replays a sequence of actions.    
 *
 * Description: A negative action is considered UNDO, a positive action is
 *   considered REDO.  For insert (I) actions UNDO means doing a delete. For
 *   delete (D) actions UNDO means doing an insert.  For update (U) actions
 *   UNDO means doing a delete on the new record followed by an insert of
 *   the old record. REDO performs the opposite operations of UNDO.
 */

create or replace function history_replay(
    p_actions bigint[]
)
returns void
as $$ 
declare
    x record;
begin
    for x in 
        select
            s.table_name,
            u.ra,
            a.action_id,
            a.action,
            a.old,
            a.new
        from
            unnest(p_actions) with ordinality u(ra, n)
            join history_actions a on a.action_id = (@ ra)
            join history_timelines t on t.timeline_id = a.timeline_id
            join history_sessions s on s.session_id = t.session_id
        order by n
    loop
        if x.ra < 0
        then -- UNDO
            case x.action
                when 'I' then
                    perform history_delete(x.table_name, x.new);
                when 'U' then
                    perform history_delete(x.table_name, x.new);
                    perform history_insert(x.table_name, x.old);
                when 'D' then
                    perform history_insert(x.table_name, x.old);
                    -- we only handle I, U, D
            end case;
        else -- REDO
            case x.action
                when 'I' then
                    perform history_insert(x.table_name, x.new);
                when 'U' then
                    perform history_delete(x.table_name, x.old);
                    perform history_insert(x.table_name, x.new);
                when 'D' then
                    perform history_delete(x.table_name, x.old);
                    -- we only handle I, U, D
            end case;
        end if;
    end loop;
end;
$$ language plpgsql;
