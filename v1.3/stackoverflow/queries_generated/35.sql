-- {"query": "35.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2232} 
with
-- recent active questions with parsed tags and calculated engagement
RecentQuestions as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    coalesce(p.ViewCount,0) as ViewCount,
    coalesce(p.AnswerCount,0) as AnswerCount,
    coalesce(p.CommentCount,0) as CommentCount,
    p.Tags,
    -- normalized tag array (works in PG: split tags like '<tag1><tag2>')
    case when p.Tags is null then array[]::text[] else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') end as TagArray,
    -- engagement metric with nonlinear weighting
    (coalesce(p.Score,0)::numeric * 3
      + ln(coalesce(p.ViewCount,1)) * 2
      + coalesce(p.AnswerCount,0) * 5
      + coalesce(p.CommentCount,0) * 1.5
      + case when p.AcceptedAnswerId is not null then 10 else 0 end
    ) as Engagement
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '365 days'
),
-- aggregate user stats including recency, activity and badge-weighted score
UserStats as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(u.Views,0) as Views,
    coalesce(u.UpVotes,0) as UpVotes,
    coalesce(u.DownVotes,0) as DownVotes,
    -- badge counts and a weighted badge score
    coalesce(sum(case when b.Class = 1 then 1 else 0 end),0) as GoldBadges,
    coalesce(sum(case when b.Class = 2 then 1 else 0 end),0) as SilverBadges,
    coalesce(sum(case when b.Class = 3 then 1 else 0 end),0) as BronzeBadges,
    (coalesce(sum(case when b.Class = 1 then 1 else 0 end),0) * 5
     + coalesce(sum(case when b.Class = 2 then 1 else 0 end),0) * 2
     + coalesce(sum(case when b.Class = 3 then 1 else 0 end),0) * 1) as BadgeScore,
    -- user recent activity: posts and comments in last year
    coalesce( (select count(*) from Posts p where p.OwnerUserId = u.Id and p.CreationDate >= now() - interval '365 days'), 0) as RecentPosts,
    coalesce( (select count(*) from Comments c where c.UserId = u.Id and c.CreationDate >= now() - interval '365 days'), 0) as RecentComments,
    -- churn-adjusted activity score
    (
      (coalesce( (select count(*) from Posts p where p.OwnerUserId = u.Id),0) * 1.2)
      + (coalesce( (select count(*) from Comments c where c.UserId = u.Id),0) * 0.3)
      + (coalesce(u.Reputation,0) / 100.0)
      + greatest(0, date_part('epoch', now() - u.LastAccessDate) / 86400.0) * -0.01
    ) as ActivityScore
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
-- compute answers and their quality metrics
AnswerMetrics as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.CreationDate,
    a.Score,
    coalesce(a.CommentCount,0) as CommentCount,
    -- length-based quality heuristic and HTML tag density
    greatest(char_length(coalesce(a.Body,''))/200,1) as BodyLengthFactor,
    (char_length(regexp_replace(coalesce(a.Body,''), '[^<>]', '', 'g')) / nullif(nullif(char_length(coalesce(a.Body,'')),0),0) ) as TagDensity,
    -- accepted boost
    case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted
  from Posts a
  left join Posts q on q.Id = a.ParentId
  where a.PostTypeId = 2
),
-- tie together questions, their top answers, and tag-based popularity
QWithAnswers as (
  select
    rq.*,
    um.UserId as OwnerUserIdStats,
    um.DisplayName as OwnerName,
    um.Reputation as OwnerReputation,
    um.BadgeScore as OwnerBadgeScore,
    am.AnswerId,
    am.OwnerUserId as AnswerOwnerId,
    am.Score as AnswerScore,
    am.CommentCount as AnswerCommentCount,
    am.BodyLengthFactor,
    am.TagDensity,
    am.IsAccepted,
    -- rank answers per question by a composite score
    rank() over (partition by rq.Id order by (coalesce(am.Score,0)*2 + coalesce(am.CommentCount,0) + coalesce(am.IsAccepted,0)*10 + am.BodyLengthFactor) desc) as AnswerRank
  from RecentQuestions rq
  left join UserStats um on um.UserId = rq.OwnerUserId
  left join AnswerMetrics am on am.QuestionId = rq.Id
),
-- compute per-tag aggregates across recent questions
TagAggregates as (
  select
    tname,
    count(*) as QuestionsWithTag,
    avg(Engagement) as AvgEngagement,
    percentile_cont(0.5) within group (order by Engagement) as MedianEngagement,
    max(Engagement) as MaxEngagement
  from RecentQuestions r
  cross join lateral unnest(r.TagArray) as tag(tname)
  group by tname
),
-- detect potentially duplicate clusters using PostLinks of type Duplicate (LinkTypeId = 3)
DuplicateClusters as (
  select
    pl.PostId as DuplicateOf,
    pl.RelatedPostId as Original,
    count(*) over (partition by pl.RelatedPostId) as ClusterSize,
    min(pl.CreationDate) over (partition by pl.RelatedPostId) as FirstDuplicateDate
  from PostLinks pl
  where pl.LinkTypeId = 3
),
-- assemble final result with lots of expressions, correlated subqueries and NULL logic
Final as (
  select
    q.Id as QuestionId,
    q.Title,
    left(nullif(q.Title,''), 200) || coalesce((' — ' || coalesce(substring(array_to_string(q.TagArray, ','),1,120)), ''), '') as TitlePreview,
    q.CreationDate,
    q.Engagement,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    -- top answer info (pick rank = 1)
    (select a.AnswerId from QWithAnswers a where a.Id = q.Id and a.AnswerRank = 1 limit 1) as TopAnswerId,
    (select a.AnswerScore from QWithAnswers a where a.Id = q.Id and a.AnswerRank = 1 limit 1) as TopAnswerScore,
    (select a.IsAccepted from QWithAnswers a where a.Id = q.Id and a.AnswerRank = 1 limit 1) as TopAnswerAccepted,
    -- owner stats
    q.OwnerName,
    q.OwnerReputation,
    q.OwnerBadgeScore,
    -- tag explosion: list top 3 tags by global AvgEngagement descending (using tag aggregates)
    (select string_agg(tname, ',' order by AvgEngagement desc) from TagAggregates tg join lateral (select unnest(q.TagArray) as tname) u on u.tname = tg.tname limit 3) as TopTagsByEngagement,
    -- duplicate info (correlated): is this question marked as duplicate of someone else or has duplicates?
    case
      when exists (select 1 from PostLinks pl where pl.PostId = q.Id and pl.LinkTypeId = 3) then 'IsDuplicateOf'
      when exists (select 1 from PostLinks pl where pl.RelatedPostId = q.Id and pl.LinkTypeId = 3) then 'HasDuplicates'
      else 'NoDuplicateRelation'
    end as DuplicateStatus,
    -- compute a volatility score combining recency, views, answers, and owner activity
    (
      (q.Engagement * ln(greatest(q.ViewCount,2)) / nullif(greatest(date_part('epoch', now() - q.CreationDate)/86400.0,1),1))
      + coalesce(q.OwnerBadgeScore,0)
      - coalesce((select max(ClusterSize) from DuplicateClusters dc where dc.Original = q.Id),0)
    ) as VolatilityScore,
    -- string-heavy expression showing a short excerpt of the most recent comment (correlated)
    (
      select left(coalesce(c.Text,''), 120) || case when char_length(coalesce(c.Text,'')) > 120 then '...' else '' end
      from Comments c
      where c.PostId = q.Id
      order by c.CreationDate desc
      limit 1
    ) as LatestCommentPreview,
    -- computed null-handling example: preferred display name fallback
    coalesce(q.OwnerName, (select u.DisplayName from Users u where u.Id = q.OwnerUserId limit 1), 'anonymous') as PreferredOwnerName
  from RecentQuestions q
)
select
  f.*,
  -- windowed percentile within final set
  percentile_cont(0.25) within group (order by VolatilityScore) over () as VolatilityQ1,
  percentile_cont(0.5) within group (order by VolatilityScore) over () as VolatilityMedian,
  percentile_cont(0.75) within group (order by VolatilityScore) over () as VolatilityQ3,
  -- rank by engagement and volatility
  rank() over (order by Engagement desc, VolatilityScore desc) as RankByEngagementVolatility
from Final f
where f.Engagement is not null
order by RankByEngagementVolatility
limit 250;