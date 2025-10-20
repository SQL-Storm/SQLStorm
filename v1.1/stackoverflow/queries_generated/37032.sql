-- {"query": "37032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2048} 
with
-- top contributors by weighted score (answers weighted higher)
UserScores as (
  select
    u.Id as UserId,
    u.DisplayName,
    sum(
      case p.PostTypeId
        when 1 then coalesce(p.Score,0) * 1      -- question score
        when 2 then coalesce(p.Score,0) * 3      -- answer score weighted
        else 0
      end
    ) as WeightedScore,
    count(case when p.PostTypeId=1 then 1 end) as Questions,
    count(case when p.PostTypeId=2 then 1 end) as Answers,
    max(u.Reputation) as Reputation
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.DisplayName
),
-- tag popularity per user (explode Tags string '<t1><t2>' into rows)
UserTagExplode as (
  select
    p.Id as PostId,
    p.OwnerUserId as UserId,
    lower(trim(t.tag)) as Tag
  from Posts p
  cross join lateral (
    select regexp_split_to_table(substring(coalesce(p.Tags,''),2,length(coalesce(p.Tags,''))-2), '><') as tag
  ) t
  where p.PostTypeId = 1 and p.OwnerUserId is not null
),
-- compute per-user per-tag metrics
UserTagStats as (
  select
    ute.UserId,
    ute.Tag,
    count(*) as QuestionsWithTag,
    sum(coalesce(p.Score,0)) as TagQuestionScore,
    avg(coalesce(p.ViewCount,0)) as AvgViews,
    max(p.CreationDate) as LastAsked
  from UserTagExplode ute
  join Posts p on p.Id = ute.PostId
  group by ute.UserId, ute.Tag
),
-- badge diversity and recency
UserBadgeStats as (
  select
    b.UserId,
    count(*) as BadgeCount,
    count(distinct b.Name) as DistinctBadgeNames,
    max(b.Date) as LastBadgeDate,
    sum(case when b.Class=1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class=2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class=3 then 1 else 0 end) as BronzeBadges
  from Badges b
  group by b.UserId
),
-- user interaction graph metrics: inbound links (others linking to user's posts) and outbound links
PostLinkStats as (
  select
    p.OwnerUserId as UserId,
    sum(case when pl.PostId = p.Id then 1 else 0 end) as OutboundLinksFromUserPosts,
    sum(case when pl.RelatedPostId = p.Id then 1 else 0 end) as InboundLinksToUserPosts
  from Posts p
  left join PostLinks pl on pl.PostId = p.Id or pl.RelatedPostId = p.Id
  where p.OwnerUserId is not null
  group by p.OwnerUserId
),
-- average answer response time for user's questions (time to first answer)
FirstAnswerTimes as (
  select
    q.OwnerUserId as UserId,
    count(a.Id) filter (where a.Id is not null) as AnsweredQuestions,
    avg(extract(epoch from (min(a.CreationDate) over (partition by q.Id) - q.CreationDate))) filter (where min(a.CreationDate) over (partition by q.Id) is not null) as AvgFirstAnswerSeconds,
    percentile_cont(0.5) within group (order by extract(epoch from (min(a.CreationDate) over (partition by q.Id) - q.CreationDate))) filter (where min(a.CreationDate) over (partition by q.Id) is not null) as MedianFirstAnswerSeconds
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1 and q.OwnerUserId is not null
  group by q.Id, q.OwnerUserId
),
-- combine first answer times aggregated per user
UserFirstAnswerAgg as (
  select
    fa.UserId,
    avg(fa.AvgFirstAnswerSeconds) as UserAvgFirstAnswerSeconds,
    avg(fa.MedianFirstAnswerSeconds) as UserMedianFirstAnswerSeconds,
    sum(fa.AnsweredQuestions) as TotalAnsweredQuestions
  from FirstAnswerTimes fa
  group by fa.UserId
),
-- votes influence: upvotes minus downvotes on user's posts
UserVoteStats as (
  select
    p.OwnerUserId as UserId,
    sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetPostVotes,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesOnPosts,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesOnPosts
  from Posts p
  join Votes v on v.PostId = p.Id
  where p.OwnerUserId is not null
  group by p.OwnerUserId
),
-- bring everything together and compute a composite ranking score with many facets
UserComposite as (
  select
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.WeightedScore,
    us.Questions,
    us.Answers,
    coalesce(ubs.BadgeCount,0) as BadgeCount,
    coalesce(ubs.DistinctBadgeNames,0) as DistinctBadgeNames,
    coalesce(pls.InboundLinksToUserPosts,0) as InboundLinks,
    coalesce(pls.OutboundLinksFromUserPosts,0) as OutboundLinks,
    coalesce(uvs.NetPostVotes,0) as NetPostVotes,
    coalesce(fta.UserAvgFirstAnswerSeconds, null) as AvgFirstAnswerSeconds,
    coalesce(fta.UserMedianFirstAnswerSeconds, null) as MedianFirstAnswerSeconds,
    -- diversity metric: badge types + tag breadth + answer/question ratio
    (coalesce(ubs.DistinctBadgeNames,0) * 2
      + (select count(distinct Tag) from UserTagStats uts where uts.UserId = us.UserId) * 3
      + (case when us.Answers+us.Questions > 0 then greatest((us.Answers::float)/(us.Questions+1),1) else 0 end) * 1.5
    ) as DiversityScore,
    -- recency boost: recent activity and recent badges
    (case when (select max(p.LastActivityDate) from Posts p where p.OwnerUserId = us.UserId) is not null
      then exp(-least(3650, extract(day from now() - max(p.LastActivityDate) over (partition by us.UserId)))/365.0)
      else 0 end) as RecencyDecay,
    -- composite raw
    (
      -- base: reputation + weighted score
      ln(1+us.Reputation) * 2.0
      + ln(1+abs(us.WeightedScore)) * sign(us.WeightedScore + 0.0) * 1.5
      + coalesce(uvs.NetPostVotes,0) * 0.8
      + coalesce(ubs.GoldBadges,0) * 5
      + coalesce(ubs.SilverBadges,0) * 2
      + coalesce(ubs.BronzeBadges,0) * 1
      + (select count(*) from Posts p where p.OwnerUserId = us.UserId and p.PostTypeId=2) * 0.6
      + (select count(*) from Posts p where p.OwnerUserId = us.UserId and p.PostTypeId=1) * 0.3
      + (select count(distinct Tag) from UserTagStats uts where uts.UserId = us.UserId) * 1.8
      + coalesce(pls.InboundLinksToUserPosts,0) * 0.4
      - coalesce(fta.UserAvgFirstAnswerSeconds, 0) / 86400.0 * 0.2
    ) * (1 + (coalesce(ubs.BadgeCount,0)/10.0)) as CompositeScore
  from UserScores us
  left join UserBadgeStats ubs on ubs.UserId = us.UserId
  left join PostLinkStats pls on pls.UserId = us.UserId
  left join UserVoteStats uvs on uvs.UserId = us.UserId
  left join UserFirstAnswerAgg fta on fta.UserId = us.UserId
)
select
  uc.UserId,
  uc.DisplayName,
  round(uc.CompositeScore::numeric,4) as CompositeScore,
  uc.Reputation,
  uc.WeightedScore,
  uc.Questions,
  uc.Answers,
  uc.BadgeCount,
  uc.DistinctBadgeNames,
  uc.InboundLinks,
  uc.OutboundLinks,
  uc.NetPostVotes,
  round(coalesce(uc.AvgFirstAnswerSeconds,0)/3600::numeric,2) as AvgFirstAnswerHours,
  round(coalesce(uc.MedianFirstAnswerSeconds,0)/3600::numeric,2) as MedianFirstAnswerHours,
  round(uc.DiversityScore::numeric,2) as DiversityScore
from UserComposite uc
order by uc.CompositeScore desc nulls last
limit 100;