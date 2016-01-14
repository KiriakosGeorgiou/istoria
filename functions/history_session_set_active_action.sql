/*
 * Caller: history_trigger_func(), GUI	    
 *
 * Use Case: To set a session's active action.	    
 *
 * Description: It's just a simple update, but under the hood the update
 *   trigger on history_sessions will a) not allow the update if p_action
 *   belongs to another session b) replay the history, undoing and redoing
 *   actions, so the underlying session table goes back to the same state as
 *   it was just after p_action first occured.	It returns the session's
 *   active action after it is set.
 */

create or replace function history_session_set_active_action(
    p_session bigint, p_action bigint
)
returns bigint
as $$ 
declare
    l_active_action_id bigint;
begin
    update history_sessions
    set active_action_id = p_action
    where session_id = p_session
    returning active_action_id into l_active_action_id;

    return l_active_action_id;
end;
$$ language plpgsql
security definer;

grant execute on function history_session_set_active_action(bigint, bigint) to public;
