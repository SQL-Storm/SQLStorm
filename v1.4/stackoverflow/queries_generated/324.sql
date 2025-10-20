-- {"query": "324.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14674} 
with base as (
  select
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.LastEditorDisplayName,
    p.LastEditDate,
    coalesce(u.Reputation, 0) as OwnerReputation,
    coalesce(link_cnt.cnt, 0) as LinkCount,
    coalesce(comment_cnt.cnt, 0) as CommentCount,
    coalesce(up_cnt.cnt, 0) as UpVotes,
    coalesce(down_cnt.cnt, 0) as DownVotes,
    coalesce(bnty.cnt, 0) as BountyTotal
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  left join (
    select PostId, count(*) as cnt
    from PostLinks
    group by PostId
  ) link_cnt on link_cnt.PostId = p.Id
  left join (
    select PostId, count(*) as cnt
    from Comments
    group by PostId
  ) comment_cnt on comment_cnt.PostId = p.Id
  left join (
    select PostId, count(*) as cnt
    from Votes
    where VoteTypeId = 2
    group by PostId
  ) up_cnt on up_cnt.PostId = p.Id
  left join (
    select PostId, count(*) as cnt
    from Votes
    where VoteTypeId = 3
    group by PostId
  ) down_cnt on down_cnt.PostId = p.Id
  left join (
    select PostId, sum(BountyAmount) as cnt
    from Votes
    where VoteTypeId in (8, 9)
    group by PostId
  ) bnty on bnty.PostId = p.Id
),
dataset as (
  select
    Id,
    Title,
    PostTypeId,
    CreationDate,
    Score,
    ViewCount,
    Tags,
    OwnerUserId,
    OwnerReputation,
    OwnerDisplayName,
    LastActivityDate,
    LastEditorDisplayName,
    LastEditDate,
    LinkCount,
    CommentCount,
    UpVotes,
    DownVotes,
    BountyTotal,
    case
      when Tags is null or length(Tags) <= 2 then 0
      else coalesce(array_length(string_to_array(substring(Tags from 2 for length(Tags) - 2), '><'), 1), 0)
    end as TagCount,
    (select max(ph.CreationDate) from PostHistory ph where ph.PostId = Id) as LastHistoryDate,
    (Score + 2 * UpVotes - DownVotes + (ViewCount * 0.1) + case when BountyTotal > 0 then 5 else 0 end) as EngagementScore,
    (case when CreationDate >= (CURRENT_TIMESTAMP - interval '365 days') then true else false end) as IsRecent
  from base
),
q1 as (
  select
    Id,
    Title,
    PostTypeId,
    CreationDate,
    Score,
    ViewCount,
    Tags,
    OwnerUserId,
    OwnerReputation,
    OwnerDisplayName,
    LastActivityDate,
    LastEditorDisplayName,
    LastEditDate,
    LinkCount,
    CommentCount,
    UpVotes,
    DownVotes,
    BountyTotal,
    TagCount,
    LastHistoryDate,
    EngagementScore,
    IsRecent
  from dataset
  where PostTypeId in (1, 2) and IsRecent
),
q2 as (
  select
    Id,
    Title,
    PostTypeId,
    CreationDate,
    Score,
    ViewCount,
    Tags,
    OwnerUserId,
    OwnerReputation,
    OwnerDisplayName,
    LastActivityDate,
    LastEditorDisplayName,
    LastEditDate,
    LinkCount,
    CommentCount,
    UpVotes,
    DownVotes,
    BountyTotal,
    TagCount,
    LastHistoryDate,
    EngagementScore,
    IsRecent
  from dataset
  where PostTypeId in (1, 2) and not IsRecent
)
select *
from (
  select q1.*, row_number() over (partition by PostTypeId order by EngagementScore desc) as rn
  from q1
  union all
  select q2.*, row_number() over (partition by PostTypeId order by EngagementScore desc) as rn
  from q2
) t
order by PostTypeId, rn
limit 500;