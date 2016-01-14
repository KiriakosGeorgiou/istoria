/*
 * Caller: history_walk()  
 *
 * Use Case: Reverse and negate the array passed, and return it.  
 *
 * Description: history_walk(A, B) returns an array of actions that can be
 *   applied to the session table to transform it from its state when A was
 *   the active action to its state when B was the active action. 
 *   history_reverse() makes it possible to implement history_walk(A, B) as
 *   history_reverse(history_walk(B, A)).
 */

create or replace function history_reverse(bigint[])
returns bigint[]
as $$
    select ARRAY(
        select - $1[i]
        from generate_subscripts($1,1) as s(i)
        order by i desc
    );
$$ language 'sql' strict immutable;
