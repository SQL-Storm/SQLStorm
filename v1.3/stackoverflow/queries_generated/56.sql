-- {"query": "56.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2325} 
with
-- compute tag explosion and normalized tag rows
QuestionTags as (
  select p.Id as QuestionId,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         trim(both '<>' from unnest(string_to_array(substring(coalesce(p.Tags,''),2, greatest(length(coalesce(p.Tags,''))-2,0)), '><')) ) as Tag
  from Posts p
  where p.PostTypeId = 1
),
-- per-question aggregates from answers, including correlated subquery and window functions
AnswerAgg as (
  select q.QuestionId,
         count(a.Id) filter (where a.PostTypeId = 2) as TotalAnswers,
         sum(a.Score) filter (where a.PostTypeId = 2) as SumAnswerScore,
         max(a.Score) filter (where a.PostTypeId = 2) as MaxAnswerScore,
         avg(a.Score) filter (where a.PostTypeId = 2) as AvgAnswerScore,
         count(distinct a.OwnerUserId) as DistinctAnswerers,
         -- time-to-first-answer via correlated subquery (may be null)
         (select min(a2.CreationDate) from Posts a2 where a2.ParentId = q.QuestionId and a2.PostTypeId = 2) as FirstAnswerDate,
         -- window: rank answers by score per question
         jsonb_agg(jsonb_build_object('AnswerId', a.Id, 'Score', a.Score, 'Owner', a.OwnerUserId) order by a.Score desc NULLS LAST, a.CreationDate asc) filter (where a.PostTypeId = 2) over (partition by q.QuestionId) as AnswersJson
  from (select distinct QuestionId from QuestionTags) q
  left join Posts a on a.ParentId = q.QuestionId
  group by q.QuestionId
),
-- votes breakdown per post using conditional aggregation and set operators to create a mini ranking of vote types
VotesPerPost as (
  select v.PostId,
         count(*) as VoteCount,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 1 then 1 else 0 end) as AcceptedByOriginator,
         sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty,
         max(v.CreationDate) as LastVoteDate
  from Votes v
  group by v.PostId
),
-- compute user reputation velocity and badge density
UserStats as (
  select u.Id as UserId,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         -- reputation per year (avoid division by zero)
         (u.Reputation::numeric / greatest( (date_part('year', age(u.LastAccessDate, u.CreationDate)) * 365 + date_part('doy', age(u.LastAccessDate, u.CreationDate))) / 365.0, 0.0001)) as RepPerYear,
         -- badge counts and tag-based split
         sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
         sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
         sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
         sum(case when b.TagBased = B'1' then 1 else 0 end) as TagBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- trending tags via combination of question activity and recent views; include NULL logic and string ops
TagActivity as (
  select qt.Tag,
         count(distinct qt.QuestionId) as QuestionCount,
         sum(coalesce(qt.ViewCount,0)) as TotalViews,
         avg(coalesce(qt.Score,0)) as AvgQuestionScore,
         max(qt.CreationDate) as NewestQuestion,
         min(qt.CreationDate) as OldestQuestion,
         -- tag popularity heuristic
         (count(distinct qt.QuestionId) * 1.0 + sum(coalesce(qt.ViewCount,0))/1000.0 + avg(coalesce(qt.Score,0))/2.0) as PopularityScore
  from QuestionTags qt
  group by qt.Tag
),
-- combine posts with votes and answer aggregates, include outer joins to capture orphans
PostEnriched as (
  select p.Id,
         p.PostTypeId,
         p.Title,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         pa.TotalAnswers,
         pa.SumAnswerScore,
         pa.MaxAnswerScore,
         pa.DistinctAnswerers,
         v.VoteCount,
         v.UpVotes,
         v.DownVotes,
         v.TotalBounty,
         -- compute quality metric with NULL-aware math and string expressions on title
         (coalesce(p.Score,0) * 0.6 + coalesce(pa.AvgAnswerScore,0) * 0.25 + (coalesce(v.UpVotes,0) - coalesce(v.DownVotes,0)) * 0.15) as QualityMetric,
         -- flag potentially duplicate by scanning PostLinks
         case when exists (select 1 from PostLinks pl where pl.PostId = p.Id and pl.LinkTypeId = 3) then true else false end as HasDuplicateLink,
         -- derive tag array for later set operations
         case when p.Tags is null then array[]::text[] else string_to_array(substring(p.Tags,2, greatest(length(p.Tags)-2,0)), '><') end as TagArray
  from Posts p
  left join AnswerAgg pa on pa.QuestionId = p.Id
  left join VotesPerPost v on v.PostId = p.Id
),
-- pick top N answers per question using ROW_NUMBER window and then aggregate some heavy text expressions
TopAnswers as (
  select aqp.QuestionId, aqp.AnswerId, aqp.Score, aqp.OwnerUserId, aqp.CreationDate
  from (
    select a.ParentId as QuestionId, a.Id as AnswerId, a.Score, a.OwnerUserId, a.CreationDate,
           row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn
    from Posts a
    where a.PostTypeId = 2
  ) aqp
  where aqp.rn <= 3
),
-- heavy correlated subquery: for each question compute number of comments on its answers within 7 days of answer creation
AnswerCommentBurst as (
  select ta.QuestionId,
         sum(ac.CommentCountWithin7Days) as CommentsOnTopAnswers7d
  from TopAnswers ta
  left join lateral (
    select count(c.Id) as CommentCountWithin7Days
    from Comments c
    where c.PostId = ta.AnswerId
      and c.CreationDate <= ta.CreationDate + interval '7 days'
      and c.CreationDate >= ta.CreationDate - interval '1 hour' -- allow small negative skew for same-second events
  ) ac on true
  group by ta.QuestionId
),
-- final selection combining many pieces; include set operators to union synthetic rows for edge cases
SelectedQuestions as (
  select p.Id as QuestionId,
         p.Title,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         pa.TotalAnswers,
         coalesce(acb.CommentsOnTopAnswers7d,0) as CommentsOnTopAnswers7d,
         te.PopularityScore,
         ue.Reputation as OwnerReputation,
         us.RepPerYear,
         p.HasDuplicateLink,
         p.QualityMetric,
         -- string normalization: condensed title (remove multiple spaces, lowercase) and length
         lower(regexp_replace(coalesce(p.Title,''), '\s+', ' ', 'g')) as NormalizedTitle,
         length(coalesce(p.Title,'')) as TitleLength
  from PostEnriched p
  left join AnswerAgg pa on pa.QuestionId = p.Id
  left join AnswerCommentBurst acb on acb.QuestionId = p.Id
  left join TagActivity te on te.Tag = (select tt.Tag from QuestionTags tt where tt.QuestionId = p.Id limit 1) -- pick first tag for heuristic
  left join Users ue on ue.Id = p.OwnerUserId
  left join UserStats us on us.UserId = ue.Id
  where p.PostTypeId = 1
),
-- synthetic union: include a row representing global aggregates to force set operator work
GlobalSummary as (
  select
    null::int as QuestionId,
    'GLOBAL_SUMMARY' as Title,
    null::int as OwnerUserId,
    min(CreationDate) as CreationDate,
    sum(Score) as Score,
    sum(ViewCount) as ViewCount,
    sum(TotalAnswers) as TotalAnswers,
    sum(CommentsOnTopAnswers7d) as CommentsOnTopAnswers7d,
    sum(PopularityScore::numeric) as PopularityScore,
    null::int as OwnerReputation,
    avg(RepPerYear) as RepPerYear,
    null::boolean as HasDuplicateLink,
    avg(QualityMetric) as QualityMetric,
    'global' as NormalizedTitle,
    0 as TitleLength
  from SelectedQuestions
)
-- final output: union SelectedQuestions with GlobalSummary and order with complicated predicate
select *
from (
  select * from SelectedQuestions
  where (coalesce(TotalAnswers,0) >= 2 and coalesce(ViewCount,0) > 100)
    or (QualityMetric > 10 and (CommentsOnTopAnswers7d > 0 or HasDuplicateLink))
  union
  select * from GlobalSummary
) allrows
where
  -- complex predicate with NULL logic and exists subquery: include rows where owner is a prolific user or global summary
  (
    QuestionId is null
    or (
      OwnerUserId is not null
      and (
        exists (select 1 from Users u where u.Id = SelectedQuestions.OwnerUserId and u.Reputation > 10000)
        or OwnerReputation > 5000
      )
    )
  )
order by
  -- order by a conditional expression mixing NULLs and arithmetic
  case when QuestionId is null then 1 else 0 end,
  coalesce(PopularityScore,0) desc,
  QualityMetric desc,
  TitleLength asc
limit 200;