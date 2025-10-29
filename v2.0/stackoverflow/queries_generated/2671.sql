-- {"query": "2671.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1255} 
with UserBadgeRank as (
  select
    u.Id as UserId,
    u.DisplayName,
    b.Class,
    count(*) as BadgeCount,
    row_number() over (partition by u.Id order by count(*) desc, b.Class) as BadgeRank
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, b.Class
), TopUserBadges as (
  select UserId, DisplayName, Class, BadgeCount
  from UserBadgeRank
  where BadgeRank = 1
), QuestionScores as (
  select
    p.Id,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.Tags,
    coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId,
    dense_rank() over (order by p.Score desc, p.ViewCount desc) as ScoreRank
  from Posts p
  where p.PostTypeId = 1
), AnswerVotesAgg as (
  select
    a.ParentId as QuestionId,
    count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
    count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
    sum(coalesce(v.BountyAmount,0)) as TotalBounty
  from Posts a
  left join Votes v on v.PostId = a.Id
  where a.PostTypeId = 2
  group by a.ParentId
), QuestionLinkCounts as (
  select
    pl.PostId,
    count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount,
    count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId
), RecentPostHistories as (
  select distinct on (ph.PostId)
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment
  from PostHistory ph
  order by ph.PostId, ph.CreationDate desc
), QuestionDetails as (
  select
    q.Id,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.Tags,
    ab.UpVotes,
    ab.DownVotes,
    ab.TotalBounty,
    q.AcceptedAnswerId,
    q.ScoreRank,
    coalesce(ql.DuplicateCount,0) as DuplicateCount,
    coalesce(ql.LinkedCount,0) as LinkedCount,
    rph.PostHistoryTypeId as LastPostHistoryType,
    rph.CreationDate as LastPostHistoryDate,
    rph.UserId as LastEditorUserId,
    rph.Comment as LastPostHistoryComment,
    u.DisplayName as OwnerDisplayName,
    u.Reputation as OwnerReputation,
    tub.Class as OwnerTopBadgeClass,
    tub.BadgeCount as OwnerTopBadgeCount
  from QuestionScores q
  left join AnswerVotesAgg ab on ab.QuestionId = q.Id
  left join QuestionLinkCounts ql on ql.PostId = q.Id
  left join RecentPostHistories rph on rph.PostId = q.Id
  left join Users u on u.Id = q.OwnerUserId
  left join TopUserBadges tub on tub.UserId = q.OwnerUserId
)
select
  qd.Id as QuestionId,
  qd.Title,
  substring(qd.Tags from 2 for char_length(qd.Tags)-2) as StrippedTags,
  qd.CreationDate,
  qd.Score,
  qd.ViewCount,
  qd.AnswerCount,
  qd.UpVotes,
  qd.DownVotes,
  qd.TotalBounty,
  qd.DuplicateCount,
  qd.LinkedCount,
  qd.LastPostHistoryType,
  qd.LastPostHistoryDate,
  qd.LastEditorUserId,
  qd.LastPostHistoryComment,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  case qd.OwnerTopBadgeClass
    when 1 then 'Gold'
    when 2 then 'Silver'
    when 3 then 'Bronze'
    else 'None'
  end as OwnerTopBadge,
  qd.OwnerTopBadgeCount,
  -- calculated field complex expression combining multiple scores and badges
  round(
    coalesce(qd.Score,0) * 0.5 +
    coalesce(qd.ViewCount,0) / 1000.0 +
    coalesce(qd.AnswerCount,0) * 1.5 +
    coalesce(qd.UpVotes,0) * 0.3 -
    coalesce(qd.DownVotes,0) * 0.7 +
    coalesce(qd.TotalBounty,0) * 2.0 +
    qd.DuplicateCount * -5 +
    qd.LinkedCount * 0.8 +
    coalesce(qd.OwnerReputation,0) / 1000.0 +
    coalesce(qd.OwnerTopBadgeCount,0) * 1.2
  ,2) as ComplexScore
from QuestionDetails qd
where
  (
    -- filter: questions created in last 3 years or highly scored or have bounty
    qd.CreationDate >= current_date - interval '3 year'
    or qd.ScoreRank <= 1000
    or qd.TotalBounty > 0
  )
  and (
    -- exclude questions with certain last history types: closed, deleted, etc.
    qd.LastPostHistoryType is null or qd.LastPostHistoryType not in (10,12,50)
  )
order by ComplexScore desc
limit 50;