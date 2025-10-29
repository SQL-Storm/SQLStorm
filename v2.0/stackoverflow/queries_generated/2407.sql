-- {"query": "2407.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1035} 
with RecursiveTagPostCounts as (
  select
    t.Id as TagId,
    t.TagName,
    count(distinct p.Id) as QuestionCount,
    sum(p.ViewCount) as TotalViews,
    avg(p.Score) as AvgScore
  from Tags t
  left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
  group by t.Id, t.TagName
  union all
  select
    rt.TagId,
    rt.TagName,
    rt.QuestionCount / 2,
    rt.TotalViews / 2,
    rt.AvgScore
  from RecursiveTagPostCounts rt
  where rt.QuestionCount > 1000
  limit 100
),
UserReputationChanges as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    p.Id as PostId,
    p.Score,
    p.Title,
    row_number() over (partition by u.Id order by p.CreationDate) as PostRank
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  where u.Reputation >= 1000
),
FilteredPosts as (
  select
    p.Id,
    p.PostTypeId,
    coalesce(p.Score, 0) as Score,
    coalesce(p.ViewCount, 0) as ViewCount,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    ph.PostHistoryTypeId,
    ph.CreationDate as HistoryDate,
    ph.UserId as EditorUserId,
    ph.Comment,
    row_number() over (partition by p.Id order by ph.CreationDate desc) as LastEditRank
  from Posts p
  left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6)
  where p.PostTypeId = 1 and p.CreationDate >= '2015-01-01'
),
RankedVotes as (
  select
    v.PostId,
    v.VoteTypeId,
    count(*) as VoteCount,
    sum(case when v.UserId is null then 0 else 1 end) as VotesWithUser,
    dense_rank() over (partition by v.PostId order by count(*) desc) as VoteRank
  from Votes v
  group by v.PostId, v.VoteTypeId
),
UserBadgeCounts as (
  select
    b.UserId,
    b.Class,
    count(*) as BadgeCount
  from Badges b
  group by b.UserId, b.Class
)
select 
  u.DisplayName,
  rp.Title as QuestionTitle,
  rp.Score as QuestionScore,
  p.Score as AnswerScore,
  rp.ViewCount,
  tc.TagName,
  UserBadgeCounts.GoldBadges,
  UserBadgeCounts.SilverBadges,
  UserBadgeCounts.BronzeBadges,
  coalesce(rank_votes.VoteCounts, 0) as TotalVotes,
  rp.LastEditRank,
  case
    when rp.Score > 100 then 'Hot'
    when rp.Score between 50 and 100 then 'Warm'
    else 'Cold'
  end as PopularityCategory,
  concat_ws(' | ', 
    coalesce(rp.Title, 'No Title'), 
    coalesce(tc.TagName, 'No Tag'),
    concat('Votes:', coalesce(rank_votes.VoteCounts::text, '0'))
  ) as Summary
from UserReputationChanges u
left join Posts p on p.ParentId = u.PostId and p.PostTypeId = 2
left join FilteredPosts rp on rp.Id = u.PostId and rp.LastEditRank = 1
left join (
  select
    rtp.TagName,
    rtp.QuestionCount,
    rtp.TotalViews,
    rtp.AvgScore
  from RecursiveTagPostCounts rtp
) tc on rp.Tags like concat('%<', tc.TagName, '>%')
left join (
  select
    PostId,
    sum(VoteCount) as VoteCounts
  from RankedVotes
  where VoteRank = 1
  group by PostId
) rank_votes on rank_votes.PostId = rp.Id
left join (
  select
    UserId,
    sum(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
    sum(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
    sum(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
  from UserBadgeCounts
  group by UserId
) UserBadgeCounts on UserBadgeCounts.UserId = u.UserId
where u.PostRank <= 3 and coalesce(rank_votes.VoteCounts, 0) > 50
order by rp.Score desc, rank_votes.VoteCounts desc
limit 100;