-- {"query": "385.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 23435} 
with
TopRep as (
  select
    row_number() over (order by u.Reputation desc) as rn,
    u.Id as UserId,
    CONCAT(u.DisplayName, ' (rep ', u.Reputation, ')') as Label,
    u.Reputation as Value,
    MAX(p.LastActivityDate) as LastActive,
    (select count(*) from Comments c where c.UserId = u.Id) as CommentCount,
    (CASE WHEN MAX(p.LastActivityDate) IS NULL THEN false ELSE true END) as IsActive
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
),
TopScore as (
  select
    row_number() over (order by SUM(p.Score) desc) as rn,
    u.Id as UserId,
    CONCAT(u.DisplayName, ' (score ', SUM(p.Score), ')') as Label,
    SUM(p.Score) as Value,
    MAX(p.LastActivityDate) as LastActive,
    (select count(*) from Comments c where c.UserId = u.Id) as CommentCount,
    (CASE WHEN MAX(p.LastActivityDate) IS NULL THEN false ELSE true END) as IsActive
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.DisplayName
)
select *
from (
  select rn, UserId, Label, Value, LastActive, CommentCount, IsActive, 'rep' as Source
  from TopRep
  where rn <= 100
  union all
  select rn, UserId, Label, Value, LastActive, CommentCount, IsActive, 'score' as Source
  from TopScore
  where rn <= 100
) s
order by LastActive desc nulls last, Value desc
limit 200;