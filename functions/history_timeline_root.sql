/*
 * Caller: history_session_actions() 
 *
 * Use Case: To determine the root timeline of a timeline. 
 *
 * Description: It walks history_timelines backwards starting at the passed
 *   timeline, until it finds a timeline with no parent action (root
 *   timeline), and it returns it.
 */

create or replace function history_timeline_root(
    p_timeline bigint
)
returns bigint
as $$ 
declare
    l_timeline bigint;
    l_parent_action_id bigint;
begin
    l_timeline := p_timeline;
    loop
        select parent_action_id into l_parent_action_id
        from history_timelines
        where timeline_id = l_timeline;

        if l_parent_action_id is null
        then
            return l_timeline;
        else
            l_timeline := history_action_timeline(l_parent_action_id);
        end if;
    end loop;
end;
$$ language plpgsql;
