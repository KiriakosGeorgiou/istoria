/*
 * Caller: The update trigger on history_sessions.active_action_id.  
 *
 * Use Case: To replay the action history to keep the session base table
 *   consistent with the update of history_sessions.active_action_id.  
 *
 * Description: Note that this function is, be design, only called when the
 *   update to history_sessions.active_action_id happens outside a
 *   trigger.  The update of history_sessions.active_action_id
 *   within history_trigger_func() does not cause this trigger function to
 *   execute.
 */

create or replace function history_sessions_trigger_func() returns trigger
as $$ 
declare
    new_session bigint;
begin 

    /*
        CROSS CHECK - useful because history_walk() will gladly walk from
        a null to any to_action and assume you meant to start from the
        first action of to_action's session.  Without this check one could
        set the active_action_id of a session to null, and then update it
        to an action in another session.
    */
    new_session := history_action_session(new.active_action_id);
    if (new_session is not null) and (new_session <> old.session_id)
    then
        raise exception 'the new active_history_action_id is from session %', new_session
        using hint = 'the actions can not be from different sessions';
    end if;

    perform history_replay(history_walk(old.active_action_id, new.active_action_id));
    return null;
end;
$$ language plpgsql;

drop trigger if exists history_sessions_tr on history_sessions;
create trigger history_sessions_tr after update of active_action_id on history_sessions
for each row
    when (pg_trigger_depth() < 1)
    execute procedure history_sessions_trigger_func();
