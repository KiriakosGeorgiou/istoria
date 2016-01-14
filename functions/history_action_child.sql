/*
 * Caller: history_session_redo()  
 *
 * Use Case: To determine the p_action 's first descendant (child) action
 *   that is in the same timeline as p_action.	
 *
 * Description: If p_action has no descendant, then p_action is returned.
 */

create or replace function history_action_child(
    p_action bigint
)
returns bigint
as $$ 
declare
    l_timeline bigint;
    l_child bigint;
begin
    if p_action is null
    then
        return null;
    end if;

    l_timeline := history_action_timeline(p_action);

    select min(action_id) into l_child
    from history_actions
    where action_id > p_action and timeline_id = l_timeline;

    return case when l_child is null then p_action else l_child end;
end;
$$ language plpgsql;
