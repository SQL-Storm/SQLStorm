-- {"query": "7028.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2561} 
with
-- recent active questions with parsed tag rows
Questions as (
  select p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount,
         coalesce(p.Tags,'') as Tags,
         -- split tags stored like: '<tag1><tag2>'
         regexp_split_to_table(substring(coalesce(p.Tags,''),2, null), '><') as Tag
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '2 years'
),
-- aggregate badge counts and most recent badge per user
UserBadges as (
  select b.UserId,
         count(*) filter (where b.Class = 1) as GoldBadges,
         count(*) filter (where b.Class = 2) as SilverBadges,
         count(*) filter (where b.Class = 3) as BronzeBadges,
         max(b.Date) as LastBadgeDate,
         string_agg(distinct b.Name, ', ' order by b.Date desc) as BadgeList
  from Badges b
  group by b.UserId
),
-- answer stats per question using window functions and correlated subqueries
AnswersPerQuestion as (
  select a.ParentId as QuestionId,
         count(*) as AnswerCountTotal,
         sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers,
         sum(case when a.Score <= 0 then 1 else 0 end) as NonPositiveAnswers,
         max(a.Score) as MaxAnswerScore,
         min(a.Score) as MinAnswerScore,
         avg(a.Score) as AvgAnswerScore,
         -- top scoring answer id(s) as comma separated
         string_agg(a.Id::text, ',' order by a.Score desc, a.CreationDate asc) filter (where rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) = 1) as TopAnswerIds
  from Posts a
  where a.PostTypeId = 2
    and a.ParentId is not null
  group by a.ParentId
),
-- compute chronic editors on a per-post basis and last edit metadata
PostEditors as (
  select ph.PostId,
         count(distinct ph.UserId) as DistinctEditors,
         count(*) as EditEvents,
         max(ph.CreationDate) as LastEditDate,
         min(ph.CreationDate) as FirstEditDate,
         -- top editor by number of edits
         (select ph2.UserId
          from PostHistory ph2
          where ph2.PostId = ph.PostId and ph2.UserId is not null
          group by ph2.UserId
          order by count(*) desc, max(ph2.CreationDate) desc
          limit 1) as TopEditorUserId
  from PostHistory ph
  where ph.PostId is not null
  group by ph.PostId
),
-- recent comment sentiment-ish metrics (score weighted)
CommentMetrics as (
  select c.PostId,
         count(*) as CommentCount,
         sum(coalesce(c.Score,0)) as CommentScoreSum,
         avg(coalesce(c.Score,0)) as CommentScoreAvg,
         -- long comments count
         sum(case when char_length(c.Text) > 200 then 1 else 0 end) as LongComments
  from Comments c
  where c.CreationDate >= now() - interval '2 years'
  group by c.PostId
),
-- link graph metrics: inbound/outbound links per post and reciprocal links
PostLinksAgg as (
  select pl.PostId,
         count(*) filter (where pl.LinkTypeId = 1) as OutboundLinks,
         count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
         count(distinct pl.RelatedPostId) as DistinctRelated,
         sum(case when exists (
               select 1 from PostLinks pl2
               where pl2.PostId = pl.RelatedPostId and pl2.RelatedPostId = pl.PostId
             ) then 1 else 0 end) as ReciprocalLinks -- expensive correlated check
  from PostLinks pl
  group by pl.PostId
),
-- put it together: per-question enriched dataset
EnrichedQuestions as (
  select q.*,
         u.Reputation,
         u.DisplayName,
         ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.LastBadgeDate, ub.BadgeList,
         a.AnswerCountTotal, a.PositiveAnswers, a.NonPositiveAnswers, a.MaxAnswerScore, a.MinAnswerScore, a.AvgAnswerScore, a.TopAnswerIds,
         pe.DistinctEditors, pe.EditEvents, pe.LastEditDate, pe.TopEditorUserId,
         cm.CommentCount, cm.CommentScoreSum, cm.CommentScoreAvg, cm.LongComments,
         pla.OutboundLinks, pla.DuplicateLinks, pla.DistinctRelated, pla.ReciprocalLinks
  from Questions q
  left join Users u on u.Id = q.OwnerUserId
  left join UserBadges ub on ub.UserId = q.OwnerUserId
  left join AnswersPerQuestion a on a.QuestionId = q.Id
  left join PostEditors pe on pe.PostId = q.Id
  left join CommentMetrics cm on cm.PostId = q.Id
  left join PostLinksAgg pla on pla.PostId = q.Id
),
-- compute per-tag aggregates over enriched questions
TagAggregates as (
  select Tag,
         count(*) as Questions,
         sum(AnswerCount) filter (where AnswerCount is not null) as TotalAnswers,
         avg(coalesce(Score,0)) as AvgQuestionScore,
         sum(case when AnswerCount > 0 then 1 else 0 end) as QuestionsWithAnswers,
         sum(case when AnswerCount = 0 or AnswerCount is null then 1 else 0 end) as OpenQuestions,
         avg(coalesce(ViewCount,0)) as AvgViews,
         sum(coalesce(CommentCount,0)) as TotalComments,
         avg(coalesce(AvgAnswerScore,0)) as AvgAnswerScorePerQuestion,
         -- diversity of askers' reputation (stdev)
         case when count(distinct OwnerUserId) > 1 then sqrt( (sum( (coalesce(Reputation,0)::bigint * coalesce(Reputation,0)::bigint )) - (sum(coalesce(Reputation,0))::bigint * sum(coalesce(Reputation,0))::bigint)/count(*) ) / (count(*) - 1) ) else null end as ReputationStdDev
  from EnrichedQuestions
  group by Tag
),
-- rank tags by combined popularity and engagement with complex score
TagRank as (
  select ta.*,
         -- composite score: weighted sum of normalized metrics with null handling and sqrt/stretch
         (
           (coalesce(ta.Questions,0)::double precision / nullif((select max(Questions) from TagAggregates),0)) * 0.35
           + (coalesce(ta.TotalAnswers,0)::double precision / nullif((select max(TotalAnswers) from TagAggregates),0)) * 0.25
           + (coalesce(ta.AvgViews,0)::double precision / nullif((select max(AvgViews) from TagAggregates),0)) * 0.2
           + (coalesce(ta.TotalComments,0)::double precision / nullif((select max(TotalComments) from TagAggregates),0)) * 0.1
           + (coalesce(ta.AvgAnswerScorePerQuestion,0)::double precision / nullif((select max(AvgAnswerScorePerQuestion) from TagAggregates),0)) * 0.1
         ) as CompositeScore
  from TagAggregates ta
),
-- final selection: join back to sample of top questions per tag with tricky predicates and set operations
TopQuestionsPerTag as (
  select tr.Tag, tr.CompositeScore,
         eq.Id as QuestionId, eq.Title, eq.OwnerUserId, eq.Reputation as OwnerReputation,
         eq.Score, eq.ViewCount, eq.AnswerCount,
         eq.CommentCount, eq.AvgAnswerScore, eq.MaxAnswerScore, eq.MinAnswerScore,
         eq.DistinctEditors, eq.EditEvents, eq.LastEditDate, eq.TopEditorUserId,
         -- dynamic risk level: many heuristics combined with NULL logic and string ops
         case
           when eq.Score >= 50 or eq.ViewCount >= 100000 then 'hot'
           when coalesce(eq.AnswerCount,0) = 0 and eq.ViewCount > 5000 then 'controversial'
           when coalesce(eq.DistinctEditors,0) > 5 and coalesce(eq.EditEvents,0) > 10 then 'community-curated'
           when coalesce(eq.CommentCount,0) > 20 and coalesce(eq.AvgAnswerScore,0) < 0 then 'heated'
           when eq.Score is null then 'unknown'
           else 'normal'
         end as RiskLevel,
         -- label concatenation including tag, top badge holder and some null-protected strings
         coalesce(trim(eq.Title), '<untitled>') || ' [' || tr.Tag || ']'
           || ' (score:' || coalesce(eq.Score::text,'0') || ', answers:' || coalesce(eq.AnswerCount::text,'0') || ')' as ShortLabel
  from TagRank tr
  join lateral (
    -- choose three representative questions per tag using window fn and set ops
    select e.*
    from (
      select eq.*, row_number() over (partition by eq.Tag order by coalesce(eq.Score,0) desc, coalesce(eq.ViewCount,0) desc, coalesce(eq.AnswerCount,0) desc) as rn
      from EnrichedQuestions eq
      where eq.Tag = tr.Tag
        and coalesce(eq.Score,0) > -50 -- exclude extremely downvoted posts
        and (eq.AnswerCount is null or eq.AnswerCount >= 0) -- odd null logic
    ) eq
    where eq.rn <= 3
    order by eq.rn
  ) eq on true
)
select tq.Tag,
       tq.CompositeScore,
       tq.QuestionId,
       tq.ShortLabel,
       tq.OwnerUserId,
       u.DisplayName as OwnerName,
       tq.OwnerReputation,
       tq.Score,
       tq.ViewCount,
       tq.AnswerCount,
       tq.CommentCount,
       tq.MaxAnswerScore,
       tq.MinAnswerScore,
       tq.AvgAnswerScore,
       tq.DistinctEditors,
       tq.EditEvents,
       tq.LastEditDate,
       coalesce(ue.BadgeList, 'none') as OwnerBadges,
       tq.RiskLevel,
       -- add correlated subquery: median answer score computed per question from raw answers
       (select percentile_cont(0.5) within group (order by a.Score)
        from Posts a
        where a.ParentId = tq.QuestionId
          and a.PostTypeId = 2
       ) as MedianAnswerScore,
       -- set operator sample: union of recent voters (upvotes) and favorite owners (votes of type 5) limited and aggregated
       (select string_agg(distinct u2.DisplayName, ', ' order by u2.Reputation desc)
        from (
          select v.UserId from Votes v where v.PostId = tq.QuestionId and v.VoteTypeId = 2 limit 5
          union
          select v.UserId from Votes v where v.PostId = tq.QuestionId and v.VoteTypeId = 5 limit 5
       ) vv
       left join Users u2 on u2.Id = vv.UserId
       ) as RepresentativeVoters
from TopQuestionsPerTag tq
left join Users u on u.Id = tq.OwnerUserId
left join Users ue on ue.Id = tq.TopEditorUserId
where tq.CompositeScore is not null
  and tq.Tag is not null
order by tq.CompositeScore desc nulls last, tq.Tag, tq.Score desc
limit 200;