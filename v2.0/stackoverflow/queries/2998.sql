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
    count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
    count(case when vt.Name = 'DownMod' then 1 end) as DownVotes,
    sum(case when vt.Name = 'BountyStart' then coalesce(v.BountyAmount, 0) else 0 end) as TotalBountyStarted
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
LatestComments as (
  select
    c.PostId,
    c.Text as LatestCommentText,
    c.CreationDate as LatestCommentDate,
    c.UserDisplayName as LatestCommentUserName
  from (
    select
      c.*,
      row_number() over (partition by c.PostId order by c.CreationDate desc) as rn
    from Comments c
  ) c
  where c.rn = 1
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
    count(case when pl.LinkTypeName = 'Duplicate' then 1 end) as CountDuplicates
  from PostLinksWithTypes pl
  group by pl.PostId
),
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
  concat_ws(' | ',
    substring(coalesce(r.Tags, '') from 1 for 30),
    '...',
    concat('Score:', cast(r.Score as varchar))
  ) as TagScoreSummary,
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
  rank() over (partition by r.PostTypeId order by r.Score desc, r.ViewCount desc) as ScoreRank,
  case 
    when r.Score > 50 then 'HighScore'
    when r.Score > 10 then 'MediumScore'
    when r.Score is null then 'NoScore'
    else 'LowScore'
  end as ScoreCategory,
  (select string_agg(distinct coalesce(pt.Name, 'Unknown'), ', ')
   from PostTypes pt
   where pt.Id = r.PostTypeId
  ) as PostTypeName
from RecursiveCTE r
left join AggregatedVotes av on av.PostId = r.Id
left join LatestComments lc on lc.PostId = r.Id
left join UserAggregateBadges ub on ub.UserId = (
  select p.OwnerUserId from Posts p where p.Id = r.Id
)
left join DuplicatePostCounts dp on dp.PostId = r.Id
left join QuestionAnswerAvgScores qas on qas.QuestionId = r.Id
where (r.Score is not null and r.Score >= 0)
  and ((r.PostTypeId = 1 and (qas.AvgAnswerScore is null or qas.AvgAnswerScore > 1)) or r.PostTypeId = 2)
group by
  r.Id,
  r.PostTypeId,
  r.CreationDate,
  r.Tags,
  r.Score,
  r.DisplayName,
  av.UpVotes,
  av.DownVotes,
  av.TotalBountyStarted,
  lc.LatestCommentText,
  lc.LatestCommentUserName,
  lc.LatestCommentDate,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  dp.CountDuplicates,
  qas.AvgAnswerScore,
  r.ViewCount
order by r.PostTypeId, ScoreRank, r.CreationDate desc
limit 100;