-- {"query": "183.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2199} 
with post as (
  select p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.LastActivityDate,
         p.Tags
  from Posts p
  where p.PostTypeId = 1
),
recent as (
  select p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.LastActivityDate, p.Tags
  from post p
  where p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
),
vote as (
  select PostId,
         sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
  from Votes
  group by PostId
),
comment as (
  select PostId, count(*) as CommentCount
  from Comments
  group by PostId
),
joined as (
  select r.Id,
         r.Title,
         r.CreationDate,
         r.OwnerUserId,
         r.Score,
         r.ViewCount,
         r.LastActivityDate,
         r.Tags,
         coalesce(v.UpVotes, 0) as UpVotes,
         coalesce(v.DownVotes, 0) as DownVotes,
         coalesce(c.CommentCount, 0) as CommentCount,
         (case when r.Tags is null then 'untagged'
               else 'tags:' || r.Tags end) as TagInfo
  from recent r
  left join vote v on v.PostId = r.Id
  left join comment c on c.PostId = r.Id
),
ranked as (
  select *,
         dense_rank() over (order by ViewCount desc nulls last, LastActivityDate desc nulls last) as rnk
  from joined
)
select *
from ranked
order by rnk
limit 200;