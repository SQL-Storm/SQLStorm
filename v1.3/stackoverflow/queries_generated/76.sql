-- {"query": "76.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1887} 
with recursive TagPairs as (
    -- explode tags into (PostId, Tag) pairs
    select p.Id as PostId,
           trim(both '<>' from unnest(string_to_array(substring(coalesce(p.Tags,''),2, greatest(length(coalesce(p.Tags,'')) - 2,0)), '><'))) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TopQuestions as (
    -- top questions by combined score (score + answer-weighted score + view factor)
    select q.Id,
           q.Title,
           q.CreationDate,
           q.Score,
           q.ViewCount,
           coalesce(q.AnswerCount,0) as AnswerCount,
           -- normalized popularity metric
           (q.Score * 1.0) + coalesce(q.ViewCount::numeric / nullif(greatest(q.AnswerCount,1),0), q.Score) * 0.01 as Popularity
    from Posts q
    where q.PostTypeId = 1
),
AnswersAgg as (
    -- aggregated answer stats per question including correlated subquery example
    select a.ParentId as QuestionId,
           count(*) filter (where a.Score >= 0) as PosAnswers,
           count(*) filter (where a.Score < 0) as NegAnswers,
           sum(a.Score) as SumAnswerScore,
           avg(a.Score) as AvgAnswerScore,
           max(a.Score) as BestAnswerScore,
           min(a.Score) as WorstAnswerScore,
           -- correlated scalar subquery: count of distinct users who answered this question
           (select count(distinct x.OwnerUserId) from Posts x where x.ParentId = a.ParentId and x.PostTypeId = 2 and x.OwnerUserId is not null) as DistinctAnswerers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
UserBadgeStats as (
    -- badges earned and recency per user with string concatenation and null logic
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           coalesce(string_agg(distinct b.Name || '(' || date_part('year', b.Date)::text || ')', ', ' order by b.Date desc), 'NO_BADGES') as BadgesList,
           max(b.Date) as LastBadgeDate,
           count(b.Id) filter (where b.Class = 1) as GoldBadges,
           count(b.Id) filter (where b.Class = 2) as SilverBadges,
           count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionTagStats as (
    -- advanced tag co-occurrence and ranking per question using window functions
    select tp.PostId as QuestionId,
           tp.Tag,
           count(*) over (partition by tp.PostId, tp.Tag) as TagFreqOnQuestion,
           -- tag global popularity
           count(*) over (partition by tp.Tag) as GlobalTagCount,
           row_number() over (partition by tp.PostId order by count(*) over (partition by tp.Tag) desc, tp.Tag) as TagRank
    from TagPairs tp
),
QuestionEnrichment as (
    -- join a bunch of things together, including outer joins and complex predicates
    select q.Id as QuestionId,
           q.Title,
           q.CreationDate,
           q.Score as QuestionScore,
           q.ViewCount,
           coalesce(aa.SumAnswerScore,0) as SumAnswerScore,
           coalesce(aa.DistinctAnswerers,0) as DistinctAnswerers,
           qs.Tag,
           qs.TagRank,
           qs.GlobalTagCount,
           ub.UserId as OwnerId,
           ub.DisplayName as OwnerName,
           ub.Reputation as OwnerReputation,
           ub.BadgesList,
           -- calculate a synthetic quality score mixing various signals with null-aware math
           (
               greatest( (q.Score::numeric), 0) * 0.6
               + greatest(coalesce(aa.AvgAnswerScore,0),0) * 2.0
               + log(greatest(q.ViewCount,1)) * 0.4
               + (case when coalesce(ub.GoldBadges,0) > 0 then 5 else 0 end)
               - least(coalesce(aa.NegAnswers,0), 5) * 0.5
           ) as QualityScore,
           -- fancy string expression summarizing the question
           left(coalesce(q.Title,'(no title)') || ' [' || coalesce(q.Tags,'') || ']', 255) as TitleSummary
    from Posts q
    left join AnswersAgg aa on aa.QuestionId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    left join UserBadgeStats ub on ub.UserId = u.Id
    left join QuestionTagStats qs on qs.PostId = q.Id AND qs.TagRank <= 3
    where q.PostTypeId = 1
),
RankedQuestions as (
    -- rank enriched questions within tag partitions and overall
    select qe.*,
           dense_rank() over (order by qe.QualityScore desc NULLS LAST) as GlobalQualityRank,
           rank() over (partition by qe.Tag order by qe.QualityScore desc NULLS LAST) as TagQualityRank,
           ntile(10) over (order by qe.QualityScore desc NULLS LAST) as Decile
    from QuestionEnrichment qe
),
RecentActivity as (
    -- set operator example: union recent comments and recent post histories into a single activity stream
    select c.PostId as RefPostId, c.CreationDate as ActivityDate, 'COMMENT' as ActivityType, c.UserId, c.Text as ActivityText from Comments c where c.CreationDate > now() - interval '90 days'
    union all
    select ph.PostId as RefPostId, ph.CreationDate as ActivityDate, 'HISTORY' as ActivityType, ph.UserId, coalesce(ph.Comment, substring(coalesce(ph.Text,''),1,200)) as ActivityText from PostHistory ph where ph.CreationDate > now() - interval '90 days'
),
LatestActivityAgg as (
    select ra.RefPostId,
           max(ra.ActivityDate) as LastActivityDate,
           count(*) as RecentActivities,
           string_agg(distinct ra.ActivityType, ',' order by ra.ActivityType) as ActivityTypes
    from RecentActivity ra
    group by ra.RefPostId
)
select rq.QuestionId,
       rq.TitleSummary,
       rq.Tag,
       rq.TagRank,
       rq.GlobalTagCount,
       rq.OwnerName,
       rq.OwnerReputation,
       rq.BadgesList,
       rq.QuestionScore,
       rq.ViewCount,
       rq.SumAnswerScore,
       rq.DistinctAnswerers,
       rq.QualityScore,
       rq.GlobalQualityRank,
       rq.TagQualityRank,
       rq.Decile,
       la.LastActivityDate,
       la.RecentActivities,
       la.ActivityTypes,
       -- a complicated predicate mixing null logic and boolean expressions
       case
         when rq.QualityScore is null then 'UNKNOWN'
         when rq.QualityScore > 20 and rq.GlobalQualityRank <= 100 then 'HIGH_QUALITY_HOT'
         when rq.QualityScore > 10 and (rq.Decile <= 3 or rq.TagQualityRank <= 5) then 'GOOD'
         when rq.QualityScore between 0 and 10 then 'AVERAGE'
         else 'LOW'
       end as QualityCategory,
       -- show a fingerprint hash-like string (simple) for quick uniqueness checks
       md5(coalesce(rq.TitleSummary,'') || '|' || coalesce(rq.Tag,'') || '|' || coalesce(rq.OwnerName,'')) as QuickFingerprint
from RankedQuestions rq
left join LatestActivityAgg la on la.RefPostId = rq.QuestionId
where
    -- complex predicate: include either highly ranked globally or in a tag and exclude closed/very old stale posts
    (
      rq.GlobalQualityRank <= 100
      or (rq.TagQualityRank is not null and rq.TagQualityRank <= 10)
      or rq.Decile = 1
    )
    and not exists (
       -- correlated subquery to exclude posts with recent deletion votes (VoteTypeId = 10) or spam (12)
       select 1 from Votes v where v.PostId = rq.QuestionId and v.VoteTypeId in (10,12) and v.CreationDate > now() - interval '30 days'
    )
    and (rq.CreationDate > now() - interval '5 years' or rq.ViewCount > 1000)
order by rq.QualityScore desc nulls last, rq.GlobalTagCount desc, rq.QuestionId
limit 250;