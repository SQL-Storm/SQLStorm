-- {"query": "7009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1979} 
with
-- high-impact questions in last 2 years with tag parsing
RecentQuestions as (
  select p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
         coalesce(p.AnswerCount,0) as AnswerCount,
         -- extract tags into rows by splitting '<tag1><tag2>'
         regexp_split_to_table(substring(p.Tags from 2 for nullif(char_length(p.Tags)-2,0)), '><') as Tag
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '2 years'
),
-- aggregate author stats
AuthorStats as (
  select u.Id as UserId,
         u.DisplayName,
         count(rq.Id) filter (where rq.Id is not null) as RecentQuestionCount,
         sum(rq.Score) as RecentQuestionScore,
         sum(rq.ViewCount) as RecentQuestionViews,
         max(rq.CreationDate) as LastQuestionDate,
         coalesce(bc.BadgeCount,0) as BadgeCount
  from Users u
  left join RecentQuestions rq on rq.OwnerUserId = u.Id
  left join (
    select UserId, count(*) as BadgeCount
    from Badges
    group by UserId
  ) bc on bc.UserId = u.Id
  group by u.Id, u.DisplayName, bc.BadgeCount
),
-- compute per-question answer metrics and top answerer
AnswerMetrics as (
  select q.Id as QuestionId,
         q.Title,
         q.OwnerUserId as QuestionOwner,
         q.CreationDate as QuestionDate,
         q.Score as QuestionScore,
         q.ViewCount as QuestionViews,
         q.Tag,
         -- answers for the question within window
         (select count(*) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as TotalAnswers,
         -- best answer score and id
         (select a.Id from Posts a where a.ParentId = q.Id and a.PostTypeId = 2 order by a.Score desc nulls last, a.CreationDate asc limit 1) as TopAnswerId,
         (select a.Score from Posts a where a.ParentId = q.Id and a.PostTypeId = 2 order by a.Score desc nulls last, a.CreationDate asc limit 1) as TopAnswerScore,
         -- average answer score (correlated subquery)
         (select avg(a.Score) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as AvgAnswerScore,
         -- distinct answerer count
         (select count(distinct a.OwnerUserId) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2 and a.OwnerUserId is not null) as DistinctAnswerers
  from RecentQuestions q
),
-- compute temporal activity spikes per question using window functions
QuestionSpikes as (
  select am.*,
         -- number of answers in first 7 days
         sum(case when a.CreationDate <= am.QuestionDate + interval '7 days' then 1 else 0 end) over (partition by am.QuestionId) as AnswersIn7Days,
         -- number of answers in first 30 days
         sum(case when a.CreationDate <= am.QuestionDate + interval '30 days' then 1 else 0 end) over (partition by am.QuestionId) as AnswersIn30Days,
         -- time to top answer in minutes (null if no top answer)
         case when am.TopAnswerId is not null then
           extract(epoch from (select a.CreationDate from Posts a where a.Id = am.TopAnswerId) - am.QuestionDate)/60.0
         end as MinutesToTopAnswer
  from AnswerMetrics am
  left join Posts a on a.ParentId = am.QuestionId and a.PostTypeId = 2
  group by am.QuestionId, am.Title, am.OwnerUserId, am.QuestionDate, am.QuestionScore, am.QuestionViews, am.Tag,
           am.TotalAnswers, am.TopAnswerId, am.TopAnswerScore, am.AvgAnswerScore, am.DistinctAnswerers, am.AnswerCount, am.MinutesToTopAnswer
),
-- compute user-centric window stats: percentile ranks among recent askers
UserRanks as (
  select *,
         percent_rank() over (order by coalesce(RecentQuestionCount,0) asc) as Pr_QuestionCount,
         ntile(10) over (order by coalesce(RecentQuestionScore,0) desc) as ScoreDecile
  from AuthorStats
),
-- combine everything and compute a complex score using expressions, null logic, and string ops
ScoredQuestions as (
  select qs.QuestionId,
         qs.Title,
         qs.Tag,
         qs.QuestionOwner,
         coalesce(u.DisplayName, 'anonymous') as OwnerDisplay,
         qs.QuestionDate,
         qs.QuestionScore,
         qs.QuestionViews,
         qs.TotalAnswers,
         coalesce(qs.TopAnswerId, -1) as TopAnswerId,
         coalesce(qs.TopAnswerScore, 0) as TopAnswerScore,
         coalesce(qs.AvgAnswerScore, 0) as AvgAnswerScore,
         coalesce(qs.DistinctAnswerers, 0) as DistinctAnswerers,
         coalesce(qs.AnswersIn7Days,0) as AnswersIn7Days,
         coalesce(qs.AnswersIn30Days,0) as AnswersIn30Days,
         qs.MinutesToTopAnswer,
         -- normalized view factor (logarithmic), guard against zero/null
         case when qs.QuestionViews is null then 0
              when qs.QuestionViews <= 0 then 0
              else ln(qs.QuestionViews + 1) end as LogViews,
         -- recency penalty (questions older get small penalty)
         greatest(0.0, 1 - extract(epoch from (now() - qs.QuestionDate)) / (60*60*24*365*2)) as RecencyWeight,
         -- textual complexity: length of title plus number of tag chars
         char_length(coalesce(qs.Title,'')) + char_length(coalesce(qs.Tag,'')) as TitleTagComplexity,
         -- composite score mixing many factors, using null-safe coalesce and conditional bonuses
         (
           -- base: weighted view + score
           (coalesce(ln(qs.QuestionViews+1),0) * 1.2)
           + (coalesce(qs.QuestionScore,0) * 3)
           -- answers boost (diminishing)
           + (power(coalesce(qs.TotalAnswers,0)::numeric, 0.8) * 2)
           -- top answer quality
           + (case when qs.TopAnswerScore is null then 0 else qs.TopAnswerScore * 1.5 end)
           -- average answer quality scaled
           + (coalesce(qs.AvgAnswerScore,0) * least(3, coalesce(qs.DistinctAnswerers,0)))
           -- recency multiplier
           ) * greatest(0.25, greatest(RecencyWeight, 0.01))
         +
         -- penalty for slow top answer arrival
         - coalesce(qs.MinutesToTopAnswer, 100000) / 1440.0
         +
         -- badge bonus from owner (if any)
         coalesce(u.BadgeCount,0) * 0.5
         +
         -- textual complexity bonus (non-linear)
         + sqrt(GREATEST(char_length(coalesce(qs.Title,''))::numeric,1)) * 0.1
         as CompositeScore
  from QuestionSpikes qs
  left join Users u on u.Id = qs.QuestionOwner
),
-- rank final results and include overlapping set operations to stress planner
Ranked as (
  select sq.*,
         row_number() over (order by sq.CompositeScore desc nulls last, sq.QuestionViews desc nulls last) as RankByScore,
         rank() over (partition by sq.Tag order by sq.CompositeScore desc) as TagRank
  from ScoredQuestions sq
)
-- final selection: top 200 overall plus top 3 per tag, unioned with a set-difference of low-activity questions,
-- demonstrating set operators and NULL logic. Use ordering and limits for benchmarking.
select *
from (
  -- top 200 overall
  select r.*,
         'Top200' as Source
  from Ranked r
  order by r.CompositeScore desc nulls last
  limit 200

  union

  -- top 3 per tag
  select r2.*,
         'Top3PerTag' as Source
  from Ranked r2
  where r2.TagRank <= 3

  union

  -- low-activity tail: questions with few views and no answers in 30 days, excluding those already in top 200
  select r3.*,
         'LowActivity' as Source
  from Ranked r3
  where r3.AnswersIn30Days = 0
    and coalesce(r3.QuestionViews,0) < 50
    and r3.CompositeScore < (
      select min(CompositeScore) from Ranked r where RankByScore <= 200
    )
) final
order by Source, CompositeScore desc nulls last, RankByScore
limit 1000;