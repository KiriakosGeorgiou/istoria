/*
 * Caller: Application. 
 *
 * Use Case: To reset the active action of session p_session to the parent
 *   of the active action, and return that parent action id. 
 *
 * Description: If the active action of session p_session has no parent,
 *   which is the case for the first action in the root timeline, then the
 *   function sets the active action to null and returns null.	This in
 *   effect means that all actions for session p_session have been undone,
 *   and there is nothing more to be undone.
 */

create or replace function history_session_undo(
    p_session bigint
)
returns bigint
as $$ 
declare
    l_active_action bigint;
begin
    update history_sessions
    set active_action_id = history_action_parent(active_action_id)
    where session_id = p_session
    returning active_action_id into l_active_action;

    return l_active_action;
end;
$$ language plpgsql
security definer;

grant execute on function history_session_undo(bigint) to public;
