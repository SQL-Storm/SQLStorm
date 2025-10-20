-- {"query": "124.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2080} 
with
-- base questions with parsed tags and some derived metrics
Questions as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    coalesce(p.Score,0) as QScore,
    coalesce(p.ViewCount,0) as Views,
    coalesce(p.AnswerCount,0) as AnswerCount,
    coalesce(p.FavoriteCount,0) as Favorites,
    -- split tags into one row per tag; tags stored as "<tag1><tag2>"
    trim(both ' ' from t.tag) as Tag,
    -- quick complexity heuristic: length of body and title combined
    greatest(0, length(coalesce(p.Body,'')) + length(coalesce(p.Title,''))) as TextComplexity
  from Posts p
  left join lateral (
    select unnest(string_to_array(substring(coalesce(p.Tags,''),2, greatest(0,length(coalesce(p.Tags,''))-2) ), '><')) as tag
  ) t on true
  where p.PostTypeId = 1
),
-- answers joined to their questions
Answers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswererUserId,
    a.CreationDate as AnswerCreationDate,
    coalesce(a.Score,0) as AScore,
    a.Body as ABody,
    a.CommentCount as ACommentCount
  from Posts a
  where a.PostTypeId = 2
),
-- latest activity per post using window
LatestActivity as (
  select
    p.Id as PostId,
    p.LastActivityDate,
    row_number() over (partition by p.Id order by p.LastActivityDate desc nulls last) as rn
  from Posts p
),
-- aggregated votes per post with conditional counts and sums
VoteAgg as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as UpVotes,
    count(*) filter (where v.VoteTypeId = 3) as DownVotes,
    count(*) filter (where v.VoteTypeId in (5,15)) as SaveOrReview,
    sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStartedTotal,
    count(distinct v.UserId) as DistinctVoters
  from Votes v
  group by v.PostId
),
-- badge influence per user (weighted by class: gold=3,silver=2,bronze=1)
BadgeScore as (
  select
    b.UserId,
    sum(case b.Class when 1 then 3 when 2 then 2 when 3 then 1 else 0 end) as BadgeWeight,
    count(*) as BadgeCount,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
-- top answerer per question using dense_rank and join to answers
TopAnswerers as (
  select
    a.QuestionId,
    a.AnswererUserId,
    a.AnswerId,
    a.AScore,
    dense_rank() over (partition by a.QuestionId order by a.AScore desc, a.AnswerCreationDate asc) as drank
  from Answers a
),
TopAnswererResolved as (
  select ta.QuestionId, ta.AnswererUserId, ta.AnswerId, ta.AScore
  from TopAnswerers ta
  where ta.drank = 1
),
-- correlated subquery: compute median answer score per question
MedianAnswerScore as (
  select
    q.QuestionId,
    (
      select coalesce(avg(scores),0)::numeric from (
        select a2.AScore as scores
        from Answers a2
        where a2.QuestionId = q.QuestionId
        order by a2.AScore
        limit 2 - (select count(*) from Answers a3 where a3.QuestionId = q.QuestionId) % 2
        offset floor((select count(*) from Answers a4 where a4.QuestionId = q.QuestionId)/2.0)::int
      ) x
    ) as MedianAnswerScore
  from (select distinct QuestionId from Answers) q
),
-- compute tag popularity by aggregation
TagStats as (
  select
    q.Tag,
    count(distinct q.QuestionId) as QuestionsWithTag,
    sum(q.Views) as TotalViews,
    avg(q.QScore) as AvgQuestionScore,
    sum(case when q.AnswerCount > 0 then 1 else 0 end) as AnsweredQuestions
  from Questions q
  group by q.Tag
),
-- recent activity marker: has recent edits or comments in last 90 days (using PostHistory/Comments)
RecentActivity as (
  select
    p.Id as PostId,
    bool_or(ph.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days') as RecentHistory,
    bool_or(c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days') as RecentComment
  from Posts p
  left join PostHistory ph on ph.PostId = p.Id
  left join Comments c on c.PostId = p.Id
  group by p.Id
),
-- generate a diverse sample of questions using set operators (union of thresholds)
SampleQuestions as (
  select q.* from Questions q where q.Views >= 10000
  union
  select q.* from Questions q where q.QScore >= 50
  union
  select q.* from Questions q where q.TextComplexity > 10000
),
-- combine everything into a rich metric per question
QuestionMetrics as (
  select
    s.QuestionId,
    s.Title,
    s.OwnerUserId,
    s.CreationDate,
    s.Tag,
    s.QScore,
    s.Views,
    s.AnswerCount,
    s.Favorites,
    s.TextComplexity,
    coalesce(v.UpVotes,0) as UpVotes,
    coalesce(v.DownVotes,0) as DownVotes,
    coalesce(v.SaveOrReview,0) as SaveOrReview,
    coalesce(b.BadgeWeight,0) as OwnerBadgeWeight,
    coalesce(t.AnswererUserId, -1) as TopAnswererUserId,
    coalesce(t.AScore,0) as TopAnswerScore,
    coalesce(m.MedianAnswerScore,0) as MedianAnswerScore,
    rs.RecentHistory,
    rs.RecentComment,
    row_number() over (partition by s.Tag order by s.Views desc nulls last, s.QScore desc nulls last) as TagRank
  from SampleQuestions s
  left join VoteAgg v on v.PostId = s.QuestionId
  left join BadgeScore b on b.UserId = s.OwnerUserId
  left join TopAnswererResolved t on t.QuestionId = s.QuestionId
  left join MedianAnswerScore m on m.QuestionId = s.QuestionId
  left join RecentActivity rs on rs.PostId = s.QuestionId
)
select
  qm.QuestionId,
  left(qm.Title, 120) as ShortTitle,
  qm.Tag,
  qm.QScore,
  qm.Views,
  qm.AnswerCount,
  qm.Favorites,
  qm.TextComplexity,
  qm.UpVotes,
  qm.DownVotes,
  qm.SaveOrReview,
  qm.OwnerBadgeWeight,
  qm.TopAnswererUserId,
  qm.TopAnswerScore,
  round(qm.MedianAnswerScore::numeric,2) as MedianAnswerScore,
  -- computed score: blend multiple signals with NULL-safe math and exponential decay for age
  (
    (coalesce(qm.QScore,0) * 1.5)
    + log(1 + qm.Views)::numeric
    + (coalesce(qm.UpVotes,0) - coalesce(qm.DownVotes,0)) * 2
    + coalesce(qm.Favorites,0) * 3
    + coalesce(qm.OwnerBadgeWeight,0) * 1.2
    + coalesce(qm.TopAnswerScore,0) * 1.1
    - coalesce(qm.MedianAnswerScore,0) * 0.5
    - (case when qm.RecentHistory or qm.RecentComment then 0 else 5 end)
  ) * pow(0.999, extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - qm.CreationDate))/86400.0) as CompositeSignal,
  -- tag-level context
  ts.QuestionsWithTag,
  ts.TotalViews as TagTotalViews,
  ts.AvgQuestionScore as TagAvgScore,
  ts.AnsweredQuestions as TagAnsweredCount,
  -- complexity label with conditional expressions and NULL logic
  case
    when qm.TextComplexity is null then 'unknown'
    when qm.TextComplexity > 50000 then 'very_high'
    when qm.TextComplexity > 20000 then 'high'
    when qm.TextComplexity > 5000 then 'medium'
    else 'low'
  end as ComplexityLabel,
  -- heuristic: whether top answerer is also the owner (self-answered) or community
  case
    when qm.TopAnswererUserId = qm.OwnerUserId then 'self_answered'
    when qm.TopAnswererUserId = -1 then 'no_answers'
    else 'others_answered'
  end as OwnershipAnswerRelation
from QuestionMetrics qm
left join TagStats ts on ts.Tag = qm.Tag
order by CompositeSignal desc nulls last, qm.Views desc
limit 250;