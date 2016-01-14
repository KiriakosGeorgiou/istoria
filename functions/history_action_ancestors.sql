/*
 * Caller: history_session_actions()	    
 *
 * Use Case: This is used for the ordering of actions in
 *   history_session_actions().     
 *
 * Description: For an action on a root timeline it returns an empty array.
 *   For a p_action that's not on a root timeline, it returns an array with
 *   the action ids of the parent action of each timeline starting from the
 *   root timeline and ending at the timeline of p_action.  So if p_action
 *   11 belongs to timeline 5 that has a parent action of 8, which is on
 *   timeline 4 that has a parent action of 3 which is on timeline 1 with no
 *   parent, then this function will return the array {3,8}.
 */

create or replace function history_action_ancestors(
    p_action bigint
)
returns bigint[]
as $$ 
declare
    l_ancestors bigint[] = ARRAY[]::bigint[]; -- empty array
    l_parent bigint;
begin
    l_parent := history_action_timeline_parent(p_action);
    loop
        if l_parent is null
        then
            return l_ancestors;
        else
            l_ancestors := l_parent || l_ancestors;
            l_parent := history_action_timeline_parent(l_parent);
        end if;
    end loop;
end;
$$ language plpgsql;
