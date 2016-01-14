/*
 * Caller: history_sessions_trigger_func()   
 *
 * Use Case: To determine the sequence of actions that should be replayed in
 *   order to transform the session table from its state when p_from_action
 *   was the active action to its state when p_to_action was the active
 *   action.  
 *
 * Description: A negative action means undo it, a positive action means
 *   redo it.  This function is recursive, but it avoids deep recursion.
 */

create or replace function history_walk(
    p_from_action bigint, p_to_action bigint
)
returns bigint[]
as $$ 
declare
    l_first_action_in_session bigint;
    l_from_session bigint;
    l_to_session bigint;
    l_actions bigint[] = ARRAY[]::bigint[]; -- empty array
begin
    if p_from_action is null and p_to_action is null
    then -- noop
        return l_actions;
    end if;

    l_from_session := history_action_session(p_from_action);
    l_to_session := history_action_session(p_to_action);

    if p_to_action is null
    then
        l_first_action_in_session := history_session_first_action(l_from_session);
        return history_walk(p_from_action, l_first_action_in_session) || -l_first_action_in_session;
    end if;

    if p_from_action is null
    then
        l_first_action_in_session := history_session_first_action(l_to_session);
        return l_first_action_in_session || history_walk(l_first_action_in_session, p_to_action);
    end if;

    if l_from_session <> l_to_session
    then
        raise exception 'p_from_action session = %, p_to_action session = %', l_from_session, l_to_session
            using hint = 'the actions can not be from different sessions';
    end if;

    if p_from_action = p_to_action
    then -- base case, noop
        return l_actions;
    end if;

    while p_from_action > p_to_action
    loop
        l_actions = l_actions || -p_from_action;
        p_from_action := history_action_parent(p_from_action);
    end loop;

    /*
        We have no way of walking the action histories when p_from_action < p_to_action
        but we can walk backwards and then reverse the order and negate the actions.
    */
    return l_actions || history_reverse(history_walk(p_to_action, p_from_action));
end;
$$ language plpgsql;
