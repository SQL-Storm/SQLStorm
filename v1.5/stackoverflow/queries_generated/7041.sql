-- {"query": "7041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2727} 
with
-- recent active questions with parsed tags and synthetic tag score
RecentQuestions as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    coalesce(p.AnswerCount,0) as AnswerCount,
    coalesce(p.FavoriteCount,0) as FavoriteCount,
    -- normalize tags: remove surrounding <> and split into array (Postgres-ish)
    case when p.Tags is null then array[]::text[] else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') end as TagArray,
    -- heuristic tag weight: length(title) * score factor + view factor
    (char_length(coalesce(p.Title,'')) * greatest(p.Score,0) + coalesce(p.ViewCount,0)/10.0 + coalesce(p.FavoriteCount,0)*50) as QuestionHotness
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '730 days'  -- last 2 years
),
-- compute per-user aggregates including recent activity windows and badge-derived boost
UserAggregates as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionsAsked,
    count(distinct p.Id) filter (where p.PostTypeId=2) as AnswersGiven,
    sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotesOnPosts,
    -- active in last 90/30/7 days
    sum(case when p.CreationDate >= now() - interval '90 days' then 1 else 0 end) as PostsLast90,
    sum(case when p.CreationDate >= now() - interval '30 days' then 1 else 0 end) as PostsLast30,
    sum(case when p.CreationDate >= now() - interval '7 days' then 1 else 0 end) as PostsLast7,
    -- badge boost: gold=5 silver=2 bronze=1 summed per user
    coalesce(sum(case when b.Class = 1 then 5 when b.Class = 2 then 2 when b.Class = 3 then 1 else 0 end),0) as BadgeBoost
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Votes v on v.PostId = p.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- for each question compute aggregated answer stats, top answerer and accept stats
QuestionAnswerStats as (
  select
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId as QuestionOwnerId,
    q.CreationDate as QuestionCreation,
    q.QuestionHotness,
    q.TagArray,
    count(a.Id) as TotalAnswers,
    sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers,
    sum(coalesce(a.Score,0)) as AnswersScoreSum,
    max(a.Score) as MaxAnswerScore,
    -- accepted answer indicator and its score
    case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    (select coalesce(score,0) from Posts aa where aa.Id = q.AcceptedAnswerId) as AcceptedAnswerScore,
    -- top answerer by score (ties broken by earliest)
    (select a2.OwnerUserId from Posts a2 where a2.ParentId = q.Id and a2.PostTypeId = 2
       order by coalesce(a2.Score,0) desc nulls last, a2.CreationDate asc nulls last limit 1) as TopAnswererId,
    (select a3.Id from Posts a3 where a3.ParentId = q.Id and a3.PostTypeId = 2
       order by coalesce(a3.Score,0) desc nulls last, a3.CreationDate asc nulls last limit 1) as TopAnswerId,
    -- median-ish answer score using window function per question (percentile_approx if available)
    (select percentile_disc(0.5) within group (order by coalesce(a4.Score,0))
       from Posts a4 where a4.ParentId = q.Id and a4.PostTypeId = 2) as MedianAnswerScore
  from RecentQuestions q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.QuestionHotness, q.TagArray, q.AcceptedAnswerId
),
-- identify interesting tag co-occurrences and per-tag performance
TagPairs as (
  select
    t1.tag as tag1,
    t2.tag as tag2,
    count(*) as PairCount,
    avg(q.QuestionHotness) as AvgHotnessForPair,
    sum(case when qa.HasAccepted=1 then 1 else 0 end) as PairAcceptedCount,
    -- synthetically score pair: popularity * hotness + accepted bias
    (count(*) * avg(q.QuestionHotness) + sum(case when qa.HasAccepted=1 then 500 else 0 end)) as PairScore
  from QuestionAnswerStats qa
  cross join lateral unnest(qa.TagArray) with ordinality as t1(tag,idx1)
  cross join lateral unnest(qa.TagArray) with ordinality as t2(tag,idx2)
  join RecentQuestions q on q.Id = qa.QuestionId
  where t1.tag < t2.tag
  group by t1.tag, t2.tag
),
-- for each user compute an expertise score by joining answers to question hotness and tag overlap with user's top tags
UserExpertise as (
  select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.BadgeBoost,
    -- sum over answers: answer_score * log(1+question_hotness)
    coalesce(sum(a.Score * ln(1 + greatest(coalesce(q.QuestionHotness,0),1))),0) as AnswerImpact,
    -- diversity: count distinct tags answered on
    coalesce(count(distinct t.tag),0) as DistinctTagsAnswered,
    -- recent activity weight
    (ua.PostsLast30 * 3 + ua.PostsLast7 * 5 + ua.PostsLast90) as RecentActivityWeight,
    -- composite expertise
    (coalesce(sum(a.Score * ln(1 + greatest(coalesce(q.QuestionHotness,0),1))),0)
       + ua.BadgeBoost * 10
       + ln(1 + ua.Reputation) * 2
       + sqrt(coalesce(count(distinct t.tag),0)) * 5) as ExpertiseScore
  from UserAggregates ua
  left join Posts a on a.OwnerUserId = ua.UserId and a.PostTypeId = 2 -- answers
  left join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  left join lateral (select unnest(case when q.Tags is null then array[]::text[] else string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><') end) as tag) t on true
  group by ua.UserId, ua.DisplayName, ua.Reputation, ua.BadgeBoost, ua.PostsLast30, ua.PostsLast7, ua.PostsLast90
),
-- pick top tag pairs and top experts for final blend
TopTagPairs as (
  select * from TagPairs
  order by PairScore desc nulls last
  limit 50
),
TopExperts as (
  select * from UserExpertise
  order by ExpertiseScore desc nulls last
  limit 200
)
-- final heavy-weighted join combining questions, top tag pairs, and experts with multiple correlated subqueries
select
  row_number() over (order by (q.QuestionHotness * 0.7 + coalesce(qa.AnswersScoreSum,0) * 0.15 + coalesce(u.ExpertiseScore,0) * 0.15) desc) as Rank,
  q.Id as QuestionId,
  left(q.Title,200) as TitleSnippet,
  q.CreationDate as AskedAt,
  q.QuestionHotness,
  qa.TotalAnswers,
  qa.PositiveAnswers,
  qa.AnswersScoreSum,
  qa.HasAccepted,
  qa.AcceptedAnswerScore,
  -- top answer and its owner
  qa.TopAnswerId,
  qa.TopAnswererId,
  -- concatenated top 3 tag pairs involving this question (if any)
  (select string_agg(tp.tag1 || '|' || tp.tag2 || ':' || tp.PairCount::text, '; ' order by tp.PairScore desc)
     from TopTagPairs tp
     where tp.tag1 = any(q.TagArray) or tp.tag2 = any(q.TagArray)
     limit 3) as TopRelatedTagPairs,
  -- best available expert among those who answered this question (correlated subquery)
  (select ue.DisplayName from UserExpertise ue
     join Posts a on a.OwnerUserId = ue.UserId and a.ParentId = q.Id and a.PostTypeId = 2
     order by ue.ExpertiseScore desc nulls last
     limit 1) as BestAnswererForThisQuestion,
  -- compute an engagement metric combining answers, views, and top expert presence
  (coalesce(qa.AnswersScoreSum,0) * 2 + coalesce(q.ViewCount,0)/20.0 + coalesce( (select ue.ExpertiseScore from UserExpertise ue
       join Posts a2 on a2.OwnerUserId = ue.UserId and a2.ParentId = q.Id and a2.PostTypeId = 2
       order by ue.ExpertiseScore desc nulls last limit 1), 0) / 10.0) as EngagementScore,
  -- complex predicate: flag as "stale but high value" if old, many views, few recent answers, and no recent edits
  case
    when q.CreationDate < now() - interval '365 days' and q.ViewCount > 10000 and qa.AnswersScoreSum < 50
         and (select max(ph.CreationDate) from PostHistory ph where ph.PostId = q.Id) < now() - interval '180 days' then 1
    else 0
  end as IsStaleHighValue,
  -- aggregated comments sentiment proxy (very synthetic): sum length of comments / count
  (select
     case when count(*) = 0 then 0 else sum(char_length(coalesce(c.Text,'')))::float / count(*) end
   from Comments c where c.PostId = q.Id) as AvgCommentLength,
  -- include a small diagnostics JSON-like string assembled with string expressions and null logic
  ('{"qId":' || q.Id || ',"tags":' || coalesce('"' || array_to_string(q.TagArray,',') || '"','null') ||
     ',"topPair":' || coalesce(
       (select '"' || tp.tag1 || ',' || tp.tag2 || '"' from TopTagPairs tp where tp.tag1 = any(q.TagArray) or tp.tag2 = any(q.TagArray) order by tp.PairScore desc limit 1),
       'null') || '}'
  ) as Diagnostics
from RecentQuestions q
left join QuestionAnswerStats qa on qa.QuestionId = q.Id
left join lateral (
  select ue.* from TopExperts ue
  where ue.UserId = qa.TopAnswererId
  order by ue.ExpertiseScore desc nulls last
  limit 1
) u on true
where
  -- complex predicate filtering: either hot or answered by top expert or belongs to top tag pairs
  (
    q.QuestionHotness >= 200
    or qa.AnswersScoreSum >= 50
    or qa.TopAnswererId in (select UserId from TopExperts)
    or exists (
      select 1 from TopTagPairs tp
      where tp.tag1 = any(q.TagArray) or tp.tag2 = any(q.TagArray)
      and tp.PairScore > (select avg(PairScore) from TopTagPairs)
    )
  )
order by (q.QuestionHotness * 0.7 + coalesce(qa.AnswersScoreSum,0) * 0.15 + coalesce(u.ExpertiseScore,0) * 0.15) desc
limit 250;