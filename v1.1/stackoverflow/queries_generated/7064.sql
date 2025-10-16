-- {"query": "7064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1821} 
with
-- recent active questions with parsed tag array and basic scores
RecentQuestions as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    coalesce(p.ViewCount,0) as Views,
    coalesce(p.AnswerCount,0) as AnswerCount,
    -- normalize tag list into rows later by splitting on >< within <...>
    case when p.Tags is null then array[]::text[] else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') end as TagArray,
    p.ClosedDate
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate > (current_timestamp - interval '730 days') -- last 2 years
),
-- expand tags to one row per tag
QuestionTags as (
  select
    q.QuestionId,
    trim(t) as Tag
  from RecentQuestions q
  cross join lateral unnest(q.TagArray) t
),
-- aggregate per tag: questions, avg score, top question id by score then views
TagAggregates as (
  select
    qt.Tag,
    count(distinct qt.QuestionId) as QuestionsPerTag,
    avg(rq.Score) as AvgQuestionScore,
    max(rq.Score) as MaxScore,
    -- pick the best question per tag using window
    (select rqi.QuestionId from RecentQuestions rqi
     join QuestionTags qti on qti.QuestionId = rqi.QuestionId
     where qti.Tag = qt.Tag
     order by rqi.Score desc nulls last, rqi.Views desc nulls last, rqi.CreationDate asc
     limit 1) as TopQuestionId
  from QuestionTags qt
  join RecentQuestions rq on rq.QuestionId = qt.QuestionId
  group by qt.Tag
  having count(distinct qt.QuestionId) > 50
),
-- answers joined to questions, include correlated subquery for accepted and best answer
QuestionAnswers as (
  select
    q.QuestionId,
    a.Id as AnswerId,
    a.OwnerUserId as AnswerOwner,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreation,
    a.Body,
    -- is this the accepted answer?
    (case when q.AcceptedAnswerId is not null and a.Id = q.AcceptedAnswerId then 1 else 0 end) as IsAccepted
  from Posts q
  join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  join RecentQuestions rq on rq.QuestionId = q.Id
),
-- best answer per question by score then earliest if tie
BestAnswers as (
  select distinct on (qa.QuestionId)
    qa.QuestionId,
    qa.AnswerId,
    qa.AnswerOwner,
    qa.AnswerScore,
    qa.IsAccepted
  from QuestionAnswers qa
  order by qa.QuestionId, qa.IsAccepted desc, qa.AnswerScore desc nulls last, qa.AnswerCreation asc
),
-- user aggregates: reputation, badges, activity windows
UserBadges as (
  select
    b.UserId,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
UserActivity as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate,
    u.DisplayName,
    u.Views as ProfileViews,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    -- engagement score: weighted combination with null handling
    (coalesce(u.Reputation,0) * 0.4 + coalesce(u.Views,0) * 0.01 + coalesce(ub.GoldBadges,0) * 10 + coalesce(ub.SilverBadges,0) * 3 + coalesce(ub.BronzeBadges,0) * 1) as EngagementScore,
    row_number() over (order by (coalesce(u.Reputation,0) * 0.4 + coalesce(u.Views,0) * 0.01) desc nulls last) as EngagementRank
  from Users u
  left join UserBadges ub on ub.UserId = u.Id
),
-- compute per-question detailed metrics combining tags, answers, best answer, author info and close history
QuestionDetails as (
  select
    rq.QuestionId,
    rq.Title,
    rq.CreationDate as QuestionCreated,
    rq.Score as QuestionScore,
    rq.Views as QuestionViews,
    rq.AnswerCount,
    rq.ClosedDate,
    ta.Tag,
    tg.QuestionsPerTag,
    tg.AvgQuestionScore,
    ba.AnswerId as BestAnswerId,
    ba.AnswerScore as BestAnswerScore,
    ba.IsAccepted as BestAnswerIsAccepted,
    ua.UserId as AskerId,
    ua.DisplayName as AskerName,
    ua.Reputation as AskerReputation,
    ua.EngagementScore as AskerEngagement,
    -- comments count via correlated subquery
    (select count(*) from Comments c where c.PostId = rq.QuestionId) as CommentCount,
    -- number of edits in last year via PostHistory
    (select count(*) from PostHistory ph where ph.PostId = rq.QuestionId and ph.CreationDate > (current_timestamp - interval '365 days')) as RecentEdits,
    -- compute a synthetic "heat" metric combining many moving parts
    (coalesce(rq.Score,0) * 2 + coalesce(rq.ViewCount,0)::double precision / 100 + coalesce(rq.AnswerCount,0) * 5
      + coalesce(ba.AnswerScore,0) * 3 + (case when ba.IsAccepted = 1 then 50 else 0 end)
      - (case when rq.ClosedDate is not null then 100 else 0 end)
      + coalesce(ua.EngagementScore,0) / 10
    ) as HeatScore
  from RecentQuestions rq
  left join QuestionTags ta on ta.QuestionId = rq.QuestionId
  left join TagAggregates tg on tg.Tag = ta.Tag
  left join BestAnswers ba on ba.QuestionId = rq.QuestionId
  left join UserActivity ua on ua.UserId = rq.OwnerUserId
),
-- rank questions within tag by heat and produce final combined view across tags, dedup top tags
RankedQuestions as (
  select
    qd.*,
    rank() over (partition by qd.Tag order by qd.HeatScore desc nulls last) as RankInTag,
    dense_rank() over (order by qd.HeatScore desc nulls last) as GlobalRank
  from QuestionDetails qd
  where qd.Tag is not null
)
select
  rq.GlobalRank,
  rq.Tag,
  rq.RankInTag,
  rq.QuestionId,
  rq.Title,
  rq.QuestionCreated,
  rq.QuestionScore,
  rq.QuestionViews,
  rq.AnswerCount,
  rq.BestAnswerId,
  rq.BestAnswerScore,
  rq.BestAnswerIsAccepted,
  rq.AskerId,
  rq.AskerName,
  rq.AskerReputation,
  rq.AskerEngagement,
  rq.QuestionsPerTag,
  round(coalesce(rq.AvgQuestionScore,0)::numeric,2) as TagAvgScore,
  rq.CommentCount,
  rq.RecentEdits,
  -- some stringy derivations and null-aware labels
  (case
     when rq.ClosedDate is not null then concat('closed on ', to_char(rq.ClosedDate,'YYYY-MM-DD'))
     when rq.BestAnswerIsAccepted = 1 then 'has accepted answer'
     when rq.AnswerCount > 0 then concat(rq.AnswerCount, ' answers (no accept)')
     else 'no answers'
   end) as StatusNote,
  rq.HeatScore
from RankedQuestions rq
where rq.QuestionsPerTag >= 100 -- focus on relatively large tags
  and rq.GlobalRank <= 1000
order by rq.GlobalRank, rq.Tag, rq.RankInTag;