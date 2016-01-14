/*
 * Caller: Application. 
 *
 * Use Case: To advance the active action of session p_session to the first
 *   descendant action (child) of the active action, in the same timeline. 
 *
 * Description: If the active action of session p_session is null, then the
 *   active action of session p_session is set to the first action of
 *   session p_session.
 */

create or replace function history_session_redo(
    p_session bigint
)
returns bigint
as $$ 
declare
    l_active_action_id bigint;
begin
    update history_sessions
    set active_action_id =
        case when active_action_id is null
            then history_session_first_action(p_session)
            else history_action_child(active_action_id)
        end
    where session_id = p_session
    returning active_action_id into l_active_action_id;

    return l_active_action_id;
end;
$$ language plpgsql
security definer;

grant execute on function history_session_redo(bigint) to public;
