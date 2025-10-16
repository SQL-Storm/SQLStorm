-- {"query": "7033.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1822} 
with
-- recent active questions with tag normalization and computed metrics
RecentQuestions as (
  select
    p.Id as QuestionId,
    p.Title,
    coalesce(p.OwnerUserId, -1) as OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    regexp_split_to_table(substring(coalesce(p.Tags,''),2,length(coalesce(p.Tags,'')) - 2), '><') as TagName -- explode tags
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate > now() - interval '3 years'
),
-- aggregate tag popularity and avg metrics per tag
TagStats as (
  select
    TagName,
    count(*) as QuestionsWithTag,
    avg(Score) filter (where Score is not null) as AvgScore,
    avg(ViewCount) filter (where ViewCount is not null) as AvgViews,
    percentile_cont(0.75) within group (order by Score) as ScoreP75
  from RecentQuestions
  group by TagName
),
-- pick top tags by composite score
TopTags as (
  select TagName
  from TagStats
  order by (QuestionsWithTag * coalesce(AvgViews,0) + coalesce(AvgScore,0)*100) desc
  limit 50
),
-- best answer stats: count answers, avg score, time-to-accept
AnswerMetrics as (
  select
    a.ParentId as QuestionId,
    count(*) filter (where a.PostTypeId = 2) as AnswerCount,
    avg(a.Score) filter (where a.PostTypeId = 2) as AvgAnswerScore,
    min(a.CreationDate) filter (where a.PostTypeId = 2) as FirstAnswerDate,
    case when exists (
        select 1 from Posts p2 where p2.Id = max(a.Id) over (partition by a.ParentId) and p2.Id = (select AcceptedAnswerId from Posts q where q.Id = a.ParentId)
      ) then 1 else 0 end as HasAcceptedByWindow -- trick: correlated via window
  from Posts a
  where a.PostTypeId = 2
  group by a.ParentId
),
-- compute user contribution and recency-weighted reputation
UserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
    count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswersGiven,
    sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) filter (where v.PostId is not null) as NetVotesReceived,
    -- recency weight: more recent users get a small boost
    greatest(0, date_part('year', age(now(), u.CreationDate)) * -1 + coalesce(u.Reputation,0)/100) as RecencyWeightedScore
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Posts p2 on p2.OwnerUserId = u.Id
  left join Votes v on v.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
-- identify suspicious or extreme posts using complex predicates
SuspiciousPosts as (
  select
    p.Id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    -- complex boolean: high score with low views OR high negative score OR many comments with low owner reputation
    ( (p.Score >= 50 and coalesce(p.ViewCount,0) < 1000)
      or (p.Score <= -5)
      or (p.CommentCount >= 20 and coalesce(u.Reputation,0) < 100) ) as IsSuspicious
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
),
-- compute rolling window ranks per tag for recent questions
TagQuestionRank as (
  select
    rq.QuestionId,
    rq.TagName,
    rq.Title,
    rq.OwnerUserId,
    rq.CreationDate,
    rq.Score,
    row_number() over (partition by rq.TagName order by rq.Score desc, rq.ViewCount desc nulls last, rq.CreationDate asc) as RankInTag,
    dense_rank() over (partition by rq.TagName order by rq.Score desc) as DenseRankInTag
  from RecentQuestions rq
  where rq.TagName in (select TagName from TopTags)
),
-- collect many-to-many correlated stats: for each top tag pick hottest question and its neighbor answers/comments
HotQuestions as (
  select distinct on (t.TagName)
    t.TagName,
    tq.QuestionId,
    tq.Title,
    tq.OwnerUserId,
    tq.Score as QuestionScore,
    tq.CreationDate as QuestionCreated,
    am.AnswerCount,
    am.AvgAnswerScore,
    -- correlated subquery: time to accepted answer in hours
    (select extract(epoch from (a.CreationDate - q.CreationDate))/3600.0
     from Posts a
     join Posts q on q.Id = tq.QuestionId
     where a.ParentId = tq.QuestionId and q.AcceptedAnswerId = a.Id
     order by a.CreationDate asc
     limit 1) as HoursToAccepted,
    -- comments summary: top 3 commenters and their counts
    (select string_agg(coalesce(u.DisplayName,'[deleted]') || ':' || cnt::text, ';' order by cnt desc)
     from (
       select c.UserId, count(*) as cnt
       from Comments c
       where c.PostId = tq.QuestionId and c.UserId is not null
       group by c.UserId
       order by cnt desc
       limit 3
     ) cc
     left join Users u on u.Id = cc.UserId
    ) as TopCommenters,
    am.HasAcceptedByWindow
  from TagStats t
  join TagQuestionRank tq on tq.TagName = t.TagName
  left join AnswerMetrics am on am.QuestionId = tq.QuestionId
  where tq.RankInTag = 1
  order by t.TagName, tq.Score desc nulls last
),
-- final selection combining many things with set operations and null logic
Combined as (
  select
    h.TagName,
    h.QuestionId,
    h.Title,
    u.DisplayName as Owner,
    coalesce(h.QuestionScore,0) as QuestionScore,
    coalesce(h.AnswerCount,0) as AnswerCount,
    coalesce(h.AvgAnswerScore,0) as AvgAnswerScore,
    round(coalesce(h.HoursToAccepted, null),2) as HoursToAccepted,
    coalesce(h.TopCommenters,'') as TopCommenters,
    ua.RecencyWeightedScore,
    sp.IsSuspicious,
    case
      when sp.IsSuspicious then 'suspicious'
      when h.AnswerCount = 0 then 'unanswered'
      when h.HasAcceptedByWindow = 1 then 'answered_accepted'
      when h.AvgAnswerScore >= 5 then 'high_quality_answers'
      else 'normal'
    end as QualityLabel
  from HotQuestions h
  left join Users u on u.Id = h.OwnerUserId
  left join UserActivity ua on ua.UserId = h.OwnerUserId
  left join SuspiciousPosts sp on sp.Id = h.QuestionId
)
-- union with a small set operator exploring extreme cases: top negative, top views, and recent community-wiki
select * from Combined
union
select
  'negative-extreme' as TagName,
  p.Id as QuestionId,
  left(p.Title,200) as Title,
  coalesce(u.DisplayName,'[deleted]') as Owner,
  p.Score,
  0 as AnswerCount,
  null::numeric as AvgAnswerScore,
  null::numeric as HoursToAccepted,
  '' as TopCommenters,
  0 as RecencyWeightedScore,
  (p.Score <= -5) as IsSuspicious,
  'negative' as QualityLabel
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1 and p.Score <= -10
order by TagName, QuestionScore desc nulls last
limit 200;