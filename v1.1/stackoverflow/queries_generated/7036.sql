-- {"query": "7036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2467} 
with
-- compute tag exploded rows
QuestionTags as (
  select p.Id as QuestionId,
         trim(tag) as Tag
  from Posts p
  cross join lateral (
    select regexp_split_to_table(substring(coalesce(p.Tags,''),2, greatest(length(coalesce(p.Tags,''))-2,0)), '><') as tag
  ) t
  where p.PostTypeId = 1
),
-- user aggregate: counts, recency, and name fingerprint
UserStats as (
  select u.Id,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
         count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
         count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
         count(distinct p.Id) as QuestionsAsked,
         count(distinct a.Id) as AnswersGiven,
         nullif(md5(coalesce(u.DisplayName,'')), '') as NameHash,
         row_number() over (order by u.Reputation desc nulls last, u.LastAccessDate desc) as ReputationRank
  from Users u
  left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
  left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- heavy post-level metrics
PostMetrics as (
  select p.Id,
         p.PostTypeId,
         p.ParentId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         p.Title,
         p.OwnerUserId,
         p.AcceptedAnswerId,
         coalesce(p.AnswerCount,0) as AnswerCount,
         coalesce(p.CommentCount,0) as CommentCount,
         -- textual complexity heuristic: length + number of HTML tags
         (length(coalesce(p.Body,'')) + length(coalesce(regexp_replace(coalesce(p.Body,''),'[^<>]','','g')))) as BodyComplexity,
         -- age in days
         extract(epoch from (now() - p.CreationDate))/86400.0 as AgeDays,
         -- score velocity: score per day (avoid divide by zero)
         case when extract(epoch from (now() - p.CreationDate)) = 0 then p.Score else p.Score / (extract(epoch from (now() - p.CreationDate))/86400.0) end as ScorePerDay,
         -- popularity index (composite)
         (coalesce(p.ViewCount,0) * 0.4 + coalesce(p.Score,0) * 5 + coalesce(p.FavoriteCount,0) * 10 + coalesce(p.CommentCount,0) * 2) as PopularityIndex
  from Posts p
),
-- compute answer quality aggregated per question
AnswerQuality as (
  select q.Id as QuestionId,
         count(a.Id) as TotalAnswers,
         sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAccepted,
         avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore,
         max(a.Score) as MaxAnswerScore,
         min(a.Score) as MinAnswerScore,
         max(a.CreationDate) filter (where a.OwnerUserId is not null) as LatestAnswerDate,
         sum(case when a.Score >= 0 then 1 else 0 end) as NonNegAnswers
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
  group by q.Id
),
-- correlated top commenter per question
TopCommenterPerQuestion as (
  select c.PostId as QuestionId,
         c.UserId,
         count(*) as CommentsByUser,
         row_number() over (partition by c.PostId order by count(*) desc, max(c.CreationDate) desc) as rn
  from Comments c
  join Posts p on p.Id = c.PostId
  where p.PostTypeId = 1
  group by c.PostId, c.UserId
),
-- compute tag popularity and top questions per tag
TagStats as (
  select qt.Tag,
         count(distinct qt.QuestionId) as QuestionCount,
         avg(pm.PopularityIndex) as AvgPopularity,
         max(pm.PopularityIndex) as MaxPopularity,
         sum(case when pm.PopularityIndex > 100 then 1 else 0 end) as HotQuestions,
         percentile_cont(0.5) within group (order by pm.PopularityIndex) as MedianPopularity
  from QuestionTags qt
  join PostMetrics pm on pm.Id = qt.QuestionId
  group by qt.Tag
),
-- pick recent trending Qs: join many metrics, plus window over tags
EnrichedQuestions as (
  select pm.*,
         aq.TotalAnswers,
         aq.HasAccepted,
         aq.AvgAnswerScore,
         ts.Tag,
         ts.QuestionCount as TagQuestionCount,
         ts.AvgPopularity as TagAvgPopularity,
         tc.UserId as TopCommenterUserId,
         us.DisplayName as TopCommenterName,
         us.Reputation as TopCommenterReputation,
         row_number() over (partition by ts.Tag order by pm.PopularityIndex desc, pm.Score desc, pm.ViewCount desc) as TagRank
  from PostMetrics pm
  left join AnswerQuality aq on aq.QuestionId = pm.Id
  left join QuestionTags qt on qt.QuestionId = pm.Id
  left join TagStats ts on ts.Tag = qt.Tag
  left join TopCommenterPerQuestion tc on tc.QuestionId = pm.Id and tc.rn = 1
  left join Users us on us.Id = tc.UserId
  where pm.PostTypeId = 1
),
-- sample set: top 100 trending questions across all tags, with complex predicates
TopTrending as (
  select *
  from EnrichedQuestions
  where (PopularityIndex > 50 and (AnswerCount = 0 or HasAccepted = 0))
    or (PopularityIndex > 200 and AgeDays < 30)
    or (TagQuestionCount > 100 and TagAvgPopularity > 20)
  order by PopularityIndex desc nulls last, AgeDays asc nulls last
  limit 100
),
-- compute for each trending question a correlated subquery of similar questions using tags overlap and text similarity heuristic
SimilarQuestions as (
  select t.Id as TrendingId,
         s.Id as SimilarId,
         s.Title as SimilarTitle,
         s.PopularityIndex as SimilarPopularity,
         s.ScorePerDay as SimilarScorePerDay,
         (
           select count(*)::int
           from QuestionTags qt1
           join QuestionTags qt2 on qt1.Tag = qt2.Tag
           where qt1.QuestionId = t.Id and qt2.QuestionId = s.Id
         ) as SharedTags,
         -- Jaccard-like: shared / union
         (
           (select count(*)::float
            from QuestionTags qt1
            join QuestionTags qt2 on qt1.Tag = qt2.Tag
            where qt1.QuestionId = t.Id and qt2.QuestionId = s.Id)
           /
           greatest(1.0,
             (select count(distinct Tag)::float from QuestionTags where QuestionId = t.Id)
             + (select count(distinct Tag)::float from QuestionTags where QuestionId = s.Id)
             - (select count(distinct Tag)::float
                from QuestionTags qt1
                join QuestionTags qt2 on qt1.Tag = qt2.Tag
                where qt1.QuestionId = t.Id and qt2.QuestionId = s.Id)
           )
         ) as TagSimilarity
  from TopTrending t
  join PostMetrics s on s.PostTypeId = 1 and s.Id <> t.Id
  where s.CreationDate > t.CreationDate - interval '365 days'
),
-- deduplicate similar: keep top 3 per trending question
TopSimilar as (
  select *,
         row_number() over (partition by TrendingId order by TagSimilarity desc, SimilarPopularity desc, SharedTags desc) as rn
  from SimilarQuestions
),
TopSimilarFiltered as (
  select TrendingId, SimilarId, SimilarTitle, SimilarPopularity, TagSimilarity
  from TopSimilar
  where rn <= 3 and TagSimilarity > 0
)
-- final projection: heavy SELECT with joins, window functions, set operators and NULL logic
select
  tt.Id as QuestionId,
  coalesce(nullif(tt.Title,''), '<no title>') as Title,
  tt.Tags,
  tt.CreationDate,
  tt.AgeDays,
  tt.Score,
  tt.ViewCount,
  tt.AnswerCount,
  tt.HasAccepted,
  tt.AvgAnswerScore,
  tt.BodyComplexity,
  tt.PopularityIndex,
  tt.ScorePerDay,
  tt.Tag,
  tt.TagQuestionCount,
  tt.TagAvgPopularity,
  tt.TopCommenterUserId,
  tt.TopCommenterName,
  tt.TopCommenterReputation,
  us.DisplayName as OwnerName,
  us.Reputation as OwnerReputation,
  us.ReputationRank as OwnerReputationRank,
  -- window: percentile rank of question within its tag by popularity
  percentile_rank() over (partition by tt.Tag order by tt.PopularityIndex) as TagPercentileRank,
  -- correlated scalar: fastest accepted answer time in hours if any
  (select least(99999,
         extract(epoch from min(a.CreationDate - q.CreationDate))/3600.0)
   from Posts a
   join Posts q on q.Id = tt.Id
   where a.ParentId = tt.Id and a.PostTypeId = 2 and a.Id = tt.AcceptedAnswerId
  ) as AcceptedAnswerHours,
  -- array of similar question ids (set aggregation + string expression)
  coalesce(
    (select string_agg(similar.SimilarId::text || ':' || round(similar.TagSimilarity::numeric,3)::text, ';' order by similar.TagSimilarity desc)
     from TopSimilarFiltered similar
     where similar.TrendingId = tt.Id
    ), '<none>') as SimilarSummary,
  -- existence checks with set operator: duplicated links
  exists (
    select 1
    from PostLinks pl
    where pl.PostId = tt.Id
      and pl.LinkTypeId = 3
  ) as IsMarkedDuplicate,
  -- complex predicate combining NULL logic
  case
    when tt.PopularityIndex is null then 'unknown'
    when tt.PopularityIndex > 1000 then 'viral'
    when tt.PopularityIndex > 200 then 'hot'
    when tt.PopularityIndex > 50 then 'trending'
    else 'normal'
  end as PopularityCategory
from TopTrending tt
left join Users us on us.Id = tt.OwnerUserId
where not exists (
  -- filter out questions whose owner is in the bottom 5% by reputation among those who asked > 0 questions
  select 1 from UserStats u2
  where u2.Id = tt.OwnerUserId
    and u2.Reputation < (select coalesce(percentile_cont(0.05) within group (order by Reputation),0) from UserStats where QuestionsAsked > 0)
)
order by tt.PopularityIndex desc nulls last, tt.AgeDays asc
limit 50;