-- {"query": "2998.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1116} 
with RecursiveCTE as (
  select
    p.Id,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName,
    row_number() over (partition by p.PostTypeId order by p.CreationDate asc) as RowNum
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId in (1, 2)
),
AggregatedVotes as (
  select
    v.PostId,
    count(*) filter (where vt.Name = 'UpMod') as UpVotes,
    count(*) filter (where vt.Name = 'DownMod') as DownVotes,
    sum(case when vt.Name = 'BountyStart' then v.BountyAmount else 0 end) as TotalBountyStarted
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
LatestComments as (
  select distinct on (c.PostId)
    c.PostId,
    c.Text as LatestCommentText,
    c.CreationDate as LatestCommentDate,
    c.UserDisplayName as LatestCommentUserName
  from Comments c
  order by c.PostId, c.CreationDate desc
),
UserBadgeCount as (
  select
    b.UserId,
    b.Class,
    count(*) as BadgeCount
  from Badges b
  group by b.UserId, b.Class
),
UserAggregateBadges as (
  select
    ubc.UserId,
    max(case when ubc.Class = 1 then ubc.BadgeCount else 0 end) as GoldBadges,
    max(case when ubc.Class = 2 then ubc.BadgeCount else 0 end) as SilverBadges,
    max(case when ubc.Class = 3 then ubc.BadgeCount else 0 end) as BronzeBadges
  from UserBadgeCount ubc
  group by ubc.UserId
),
PostLinksWithTypes as (
  select
    pl.PostId,
    pl.RelatedPostId,
    lt.Name as LinkTypeName
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
),
DuplicatePostCounts as (
  select
    pl.PostId,
    count(*) filter (where pl.LinkTypeName = 'Duplicate') as CountDuplicates
  from PostLinksWithTypes pl
  group by pl.PostId
),
-- correlated subquery for average score of answers per question
QuestionAnswerAvgScores as (
  select
    p1.Id as QuestionId,
    (select avg(p2.Score) from Posts p2 where p2.ParentId = p1.Id and p2.PostTypeId = 2) as AvgAnswerScore
  from Posts p1
  where p1.PostTypeId = 1
)
select 
  r.Id as PostId,
  r.PostTypeId,
  r.CreationDate,
  concat_ws(' | ', substring(coalesce(r.Tags, '') from 1 for 30), '...', concat('Score:', r.Score::text)) as TagScoreSummary,
  r.DisplayName as OwnerName,
  coalesce(av.UpVotes, 0) as UpVotes,
  coalesce(av.DownVotes, 0) as DownVotes,
  coalesce(av.TotalBountyStarted, 0) as TotalBountyStarted,
  lc.LatestCommentText,
  lc.LatestCommentUserName,
  lc.LatestCommentDate,
  coalesce(ub.GoldBadges, 0) as GoldBadges,
  coalesce(ub.SilverBadges, 0) as SilverBadges,
  coalesce(ub.BronzeBadges, 0) as BronzeBadges,
  coalesce(dp.CountDuplicates, 0) as DuplicateLinksCount,
  qas.AvgAnswerScore,
  -- window function example: rank posts by score partitioned by PostTypeId
  rank() over (partition by r.PostTypeId order by r.Score desc, r.ViewCount desc nulls last) as ScoreRank,
  case 
    when r.Score > 50 then 'HighScore'
    when r.Score > 10 then 'MediumScore'
    when r.Score is null then 'NoScore'
    else 'LowScore'
  end as ScoreCategory,
  (select string_agg(distinct coalesce(pt.Name, 'Unknown'), ', ')
   from PostTypes pt where pt.Id in (r.PostTypeId)
  ) as PostTypeName
from RecursiveCTE r
left join AggregatedVotes av on av.PostId = r.Id
left join LatestComments lc on lc.PostId = r.Id
left join UserAggregateBadges ub on ub.UserId = (select distinct OwnerUserId from Posts where Id = r.Id)
left join DuplicatePostCounts dp on dp.PostId = r.Id
left join QuestionAnswerAvgScores qas on qas.QuestionId = r.Id
where (r.Score is not null and r.Score >= 0)
  and ((r.PostTypeId = 1 and (qas.AvgAnswerScore is null or qas.AvgAnswerScore > 1)) or r.PostTypeId = 2)
order by r.PostTypeId, ScoreRank, r.CreationDate desc
limit 100;