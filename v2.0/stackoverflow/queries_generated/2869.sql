-- {"query": "2869.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1073} 
with RecursiveTagCounts as (
  select
    t.Id as TagId,
    t.TagName,
    p.Id as PostId,
    p.CreationDate,
    p.Score,
    1 as Depth
  from Tags t
  join Posts p on p.Tags like concat('%<', t.TagName, '>%')
  where p.PostTypeId = 1

  union all

  select
    rtc.TagId,
    rtc.TagName,
    pl.RelatedPostId,
    p2.CreationDate,
    p2.Score,
    rtc.Depth + 1
  from RecursiveTagCounts rtc
  join PostLinks pl on pl.PostId = rtc.PostId and pl.LinkTypeId = 1
  join Posts p2 on p2.Id = pl.RelatedPostId
  where rtc.Depth < 3
),
UserActivityRanked as (
  select
    u.Id,
    u.DisplayName,
    count(distinct b.Id) as BadgeCount,
    count(distinct p.Id) as PostCount,
    count(distinct c.Id) as CommentCount,
    rank() over (
      order by coalesce(nullif(u.Reputation,0),0) desc,
               count(distinct b.Id) desc,
               count(distinct p.Id) desc
    ) as UserRank
  from Users u
  left join Badges b on b.UserId = u.Id and b.Date > current_date - interval '365 days'
  left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > current_date - interval '365 days'
  left join Comments c on c.UserId = u.Id and c.CreationDate > current_date - interval '365 days'
  group by u.Id, u.DisplayName, u.Reputation
),
QuestionWithAnswers as (
  select
    q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionCreated,
    q.Score as QuestionScore,
    q.ViewCount,
    a.Id as AnswerId,
    a.CreationDate as AnswerCreated,
    a.Score as AnswerScore,
    u.DisplayName as OwnerName,
    (select count(*) from Comments c where c.PostId = q.Id) as QuestionComments,
    (select count(*) from Comments c where c.PostId = a.Id) as AnswerComments
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join Users u on u.Id = q.OwnerUserId
  where q.PostTypeId = 1
),
TaggedQuestions AS (
  select
    t.TagName,
    count(distinct p.Id) as QuestionCount,
    avg(p.Score) as AvgScore,
    sum(case when p.AcceptedAnswerId is not null then 1 else 0 end)::float / NULLIF(count(distinct p.Id),0) as AcceptanceRate,
    max(p.ViewCount) as MaxViews,
    string_agg(distinct u.DisplayName, ',' order by u.Reputation desc) as TopUsersByReputation
  from Tags t
  join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
  left join Users u on u.Id = p.OwnerUserId
  group by t.TagName
)
select
  q.QuestionId,
  q.Title,
  q.QuestionCreated,
  q.QuestionScore,
  q.ViewCount,
  q.AnswerId,
  q.AnswerCreated,
  q.AnswerScore,
  coalesce(q.OwnerName, 'Anonymous') as OwnerName,
  q.QuestionComments,
  q.AnswerComments,
  u.UserRank,
  u.BadgeCount,
  u.PostCount,
  u.CommentCount,
  t.TagName,
  t.QuestionCount,
  round(t.AvgScore::numeric,2) as AvgScore,
  round(t.AcceptanceRate * 100,2) as AcceptancePercent,
  t.MaxViews,
  substring(t.TopUsersByReputation from 1 for 100) as TopUsersByReputationSnippet,
  rtc.Depth as TagRelationDepth,
  rtc.Score as RelatedPostScore,
  rtc.CreationDate as RelatedPostDate
from QuestionWithAnswers q
left join UserActivityRanked u on u.Id = (select OwnerUserId from Posts where Id = q.QuestionId)
left join LATERAL (
  select TagName, QuestionCount, AvgScore, AcceptanceRate, MaxViews, TopUsersByReputation
  from TaggedQuestions t
  where q.Title is not null
  order by random()
  limit 1
) t on true
left join RecursiveTagCounts rtc on rtc.PostId = q.QuestionId and rtc.TagId = (
  select Id from Tags where TagName = t.TagName limit 1
)
where q.QuestionScore > 5
  and (q.AnswerScore is null or q.AnswerScore > 0)
  and (u.UserRank between 1 and 100 or u.UserRank is null)
order by u.UserRank nulls last, q.QuestionScore desc, rtc.Depth
limit 100;