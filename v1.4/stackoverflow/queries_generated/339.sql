-- {"query": "339.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 27135} 
with
  QStats as (
    select p.OwnerUserId as UserId,
           sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
           sum(case when p.PostTypeId = 1 then p.Score else 0 end) as QuestionTotalScore,
           max(p.LastActivityDate) as LastActivity
    from Posts p
    group by p.OwnerUserId
  ),
  VoteOnOwnPosts as (
    select p.OwnerUserId as UserId,
           sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpvotesReceived,
           sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownvotesReceived,
           sum(coalesce(v.BountyAmount, 0)) as BountyTotal
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.OwnerUserId
  ),
  GoldBadges as (
    select UserId, count(*) as GoldBadges
    from Badges
    where Class = 1
    group by UserId
  ),
  TagScores as (
    select u.Id as UserId, t.TagName, count(*) as TagHits
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) as t(TagName) on true
    where p.PostTypeId = 1
    group by u.Id, t.TagName
  ),
  TopTagOne as (
    select UserId, TagName
    from (
      select UserId, TagName, row_number() over (partition by UserId order by TagHits desc, TagName) as rn
      from TagScores
    ) s
    where rn = 1
  )
select
  u.Id as UserId,
  u.DisplayName,
  u.Reputation,
  coalesce(q.QuestionCount, 0) as QuestionCount,
  coalesce(q.QuestionTotalScore, 0) as QuestionTotalScore,
  coalesce(q.LastActivity, u.CreationDate) as LastActivityDate,
  coalesce(v.UpvotesReceived, 0) as UpvotesOnOwnedPosts,
  coalesce(v.DownvotesReceived, 0) as DownvotesOnOwnedPosts,
  coalesce(g.GoldBadges, 0) as GoldBadges,
  coalesce(v.BountyTotal, 0) as BountyTotalOnOwnedPosts,
  coalesce((select TagName from TopTagOne tto where tto.UserId = u.Id), 'N/A') as TopQuestionTag
from Users u
left join QStats q on q.UserId = u.Id
left join VoteOnOwnPosts v on v.UserId = u.Id
left join GoldBadges g on g.UserId = u.Id
order by u.Reputation desc
limit 200;