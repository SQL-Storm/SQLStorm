-- {"query": "372.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 26343} 
with
  user_base as (
    select
      u.Id as UserId,
      u.DisplayName,
      u.Reputation,
      u.Location,
      u.CreationDate,
      u.LastAccessDate
    from Users u
  ),
  tag_aggregation as (
    select ub.UserId, t.TagName, count(*) as TagUses
    from user_base ub
    join Posts p on p.OwnerUserId = ub.UserId
    cross join lateral unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) as t(TagName)
    group by ub.UserId, t.TagName
  ),
  user_top_tags as (
    select UserId, TagName, TagUses,
           row_number() over (partition by UserId order by TagUses desc) as rn
    from tag_aggregation
  ),
  usp as (
    select ub.UserId,
           count(p.Id) as TotalPosts,
           sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
           sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
           coalesce(sum(p.Score), 0) as ScoreSum,
           max(p.CreationDate) as LastPostDate
    from user_base ub
    left join Posts p on p.OwnerUserId = ub.UserId
    group by ub.UserId
  ),
  ugb as (
    select b.UserId,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
           count(*) as BadgeCount
    from Badges b
    group by b.UserId
  ),
  uc as (
    select UserId, count(*) as CommentCount
    from Comments
    group by UserId
  ),
  uv as (
    select p.OwnerUserId as UserId,
           sum(case v.VoteTypeId when 2 then 1 when 3 then -1 else 0 end) as NetVotes
    from Votes v
    join Posts p on p.Id = v.PostId
    group by p.OwnerUserId
  )
select
  ub.UserId,
  ub.DisplayName,
  ub.Reputation,
  coalesce(ub.Location, 'Unknown') as Location,
  ub.CreationDate,
  ub.LastAccessDate,
  coalesce(ugb.GoldBadges, 0) as GoldBadges,
  coalesce(ugb.SilverBadges, 0) as SilverBadges,
  coalesce(ugb.BronzeBadges, 0) as BronzeBadges,
  coalesce(ugb.BadgeCount, 0) as BadgeCount,
  coalesce(usp.TotalPosts, 0) as TotalPosts,
  coalesce(usp.QuestionCount, 0) as QuestionCount,
  coalesce(usp.AnswerCount, 0) as AnswerCount,
  coalesce(usp.ScoreSum, 0) as ScoreSum,
  usp.LastPostDate,
  coalesce(uc.CommentCount, 0) as CommentCount,
  coalesce(uv.NetVotes, 0) as NetVotes,
  (select TagName from user_top_tags utt where utt.UserId = ub.UserId and utt.rn = 1) as TopTag,
  row_number() over (partition by coalesce(ub.Location, 'Unknown') 
                   order by (ub.Reputation * 0.4 + coalesce(usp.ScoreSum, 0) * 0.3 + coalesce(uv.NetVotes, 0) * 0.2 + coalesce(ugb.BadgeCount, 0) * 0.1) desc) as LocationRank,
  (ub.Reputation * 0.4 + coalesce(usp.ScoreSum, 0) * 0.3 + coalesce(uv.NetVotes, 0) * 0.2 + coalesce(ugb.BadgeCount, 0) * 0.1) as WeightedScore,
  CASE
     WHEN ub.LastAccessDate < (CURRENT_TIMESTAMP - INTERVAL '365 days') THEN 'Idle'
     ELSE 'Active'
  END as ActivityStatus,
  (coalesce(ub.DisplayName, 'Unknown') || ' (' || cast(ub.Reputation as text) || ') - TopTag=' || coalesce((select TagName from user_top_tags utt where utt.UserId = ub.UserId and utt.rn = 1), 'None')) as SummaryString
from user_base ub
left join usp on usp.UserId = ub.UserId
left join ugb on ugb.UserId = ub.UserId
left join uc on uc.UserId = ub.UserId
left join uv on uv.UserId = ub.UserId
order by WeightedScore desc
limit 200;