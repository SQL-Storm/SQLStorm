-- {"query": "94.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2634} 
with recursive TagPairs as (
  -- explode tags into one row per tag per question
  select
    p.Id as QuestionId,
    trim(both '<>' from regexp_split_to_table(coalesce(p.Tags,''), '><')) as Tag
  from Posts p
  where p.PostTypeId = 1
),
QuestionStats as (
  -- basic aggregated stats per question including owner and accepted answer info
  select
    q.Id,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.AcceptedAnswerId,
    q.Tags,
    count(c.Id) filter (where c.CreationDate >= q.CreationDate) as CommentsSinceCreation,
    -- stringy normalized title fragment for heavier string processing
    lower(coalesce(regexp_replace(q.Title, '\s+', ' ', 'g'), '')) as NormTitle
  from Posts q
  left join Comments c on c.PostId = q.Id
  where q.PostTypeId = 1
  group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.AcceptedAnswerId, q.Tags
),
OwnerAgg as (
  -- per-owner aggregated metrics including recency, reputation buckets and badge enrichment
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate as UserCreation,
    u.LastAccessDate,
    greatest(date_part('epoch', now() - u.LastAccessDate)::int, 0) as SecondsSinceLastAccess,
    case
      when u.Reputation >= 100000 then 'platinum'
      when u.Reputation >= 10000 then 'gold'
      when u.Reputation >= 1000 then 'silver'
      when u.Reputation >= 100 then 'bronze'
      else 'newbie'
    end as RepTier,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    -- a synthetic influence score
    (u.Reputation * 0.5 + coalesce(sum(b.Class),0) * 10 + coalesce(u.Views,0) * 0.0001) as InfluenceScore
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
),
AnswerQuality as (
  -- answer-level metrics joined back to their questions; includes correlated scalar subquery to compute median-ish score
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswerOwner,
    a.CreationDate as AnswerCreated,
    a.Score as AnswerScore,
    a.CommentCount as AnswerCommentCount,
    -- ratio and null-safe arithmetic
    case when a.Score is null then 0 else (a.Score::numeric / nullif(greatest(1, q.Score),0)) end as ScoreToQuestionRatio,
    -- correlated subquery: count of other answers from same owner to any question in last year
    (select count(*) from Posts a2 where a2.PostTypeId = 2 and a2.OwnerUserId = a.OwnerUserId and a2.CreationDate >= now() - interval '365 days') as RecentAnswersByOwner,
    -- window: rank answers per question by score then by comments then by age
    rank() over (partition by a.ParentId order by a.Score desc nulls last, a.CommentCount desc nulls last, a.CreationDate asc) as AnswerRank
  from Posts a
  join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  where a.PostTypeId = 2
),
TopTags as (
  -- identify hot tags by average question view and count
  select
    tp.Tag,
    count(distinct tp.QuestionId) as QCount,
    avg(q.ViewCount) as AvgViews,
    sum(q.Score) as SumScore,
    -- string concatenation example
    string_agg(distinct coalesce(substring(q.Title from 1 for 40),''), ' || ' order by q.CreationDate desc) as RecentTitles
  from TagPairs tp
  join QuestionStats q on q.Id = tp.QuestionId
  group by tp.Tag
  having count(distinct tp.QuestionId) > 50
),
ComplexEdges as (
  -- example of outer joins + set operators: find linked questions that are duplicates or linked, plus some left-only sets
  select pl.PostId as SourceQ, pl.RelatedPostId as TargetQ, lt.Name as LinkType, pl.CreationDate
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  where exists (select 1 from Posts p where p.Id = pl.PostId and p.PostTypeId = 1)
    and exists (select 1 from Posts p2 where p2.Id = pl.RelatedPostId and p2.PostTypeId = 1)
  union
  select p.Id as SourceQ, null as TargetQ, 'UNLINKED_QUESTION' as LinkType, p.CreationDate
  from Posts p
  where p.PostTypeId = 1 and not exists (select 1 from PostLinks pl2 where pl2.PostId = p.Id)
),
WeightedQuestionSet as (
  -- put it all together: weigh questions by composite of scores, answers, owner influence, tag hotness, and link graph
  select
    qs.Id as QuestionId,
    qs.Title,
    qs.OwnerUserId,
    oa.RepTier,
    oa.InfluenceScore,
    coalesce(qs.AnswerCount,0) as AnswerCount,
    coalesce(qs.ViewCount,0) as Views,
    coalesce(qs.Score,0) as QScore,
    -- number of hot tags on the question
    (select count(distinct t.Tag) from TagPairs t join TopTags tt on tt.Tag = t.Tag where t.QuestionId = qs.Id) as HotTagCount,
    -- number of incoming duplicate links (heavier penalty)
    (select count(*) from PostLinks pl where pl.RelatedPostId = qs.Id and pl.LinkTypeId = 3) as IncomingDuplicates,
    -- number of outgoing links
    (select count(*) from PostLinks pl where pl.PostId = qs.Id) as OutgoingLinks,
    -- whether it has an accepted answer and quality of that answer (joins may be null)
    case when qs.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    aquality.AnswerScore as AcceptedAnswerScore,
    -- composite score expression with NULL-safe arithmetic and regexp-based title factors
    (
      coalesce(qs.Score,0)::numeric * 2.5
      + log(greatest(1, coalesce(qs.ViewCount,0))) * 1.2
      + coalesce(oa.InfluenceScore, 0) * 0.01
      + (coalesce((select sum(coalesce(v.BountyAmount,0)) from Votes v where v.PostId = qs.Id and v.VoteTypeId = 8),0) * 0.001)
      - greatest(0, (select count(*) from PostLinks pl where pl.RelatedPostId = qs.Id and pl.LinkTypeId = 3)) * 5
      + coalesce((select count(*) from Comments c where c.PostId = qs.Id and c.Text ~* '\\bthank(s|ed)?\\b'),0) * 0.3
      + (case when qs.NormTitle ~ 'how to|how do i|how can i' then 10 else 0 end)
      - (case when qs.NormTitle ~ 'homework|assignment' then 8 else 0 end)
      + (coalesce((select count(*) from Votes v2 where v2.PostId = qs.Id and v2.VoteTypeId = 2),0) * 1.5)
      - (coalesce((select count(*) from Votes v3 where v3.PostId = qs.Id and v3.VoteTypeId = 3),0) * 2)
      + coalesce((select avg(a.Score) from Posts a where a.ParentId = qs.Id and a.PostTypeId = 2),0) * 1.1
    ) as CompositeScore
  from QuestionStats qs
  left join OwnerAgg oa on oa.UserId = qs.OwnerUserId
  left join Posts aquality on aquality.Id = qs.AcceptedAnswerId
),
RankedQuestions as (
  select
    wq.*,
    row_number() over (order by wq.CompositeScore desc nulls last) as GlobalRank,
    dense_rank() over (partition by wq.RepTier order by wq.CompositeScore desc nulls last) as TierRank,
    ntile(10) over (order by wq.CompositeScore desc nulls last) as Decile
  from WeightedQuestionSet wq
),
FinalContext as (
  -- pick top N questions with contextual joins and a correlated subquery to fetch related recent edits and histories
  select
    rq.QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.RepTier,
    rq.InfluenceScore,
    rq.CompositeScore,
    rq.GlobalRank,
    rq.TierRank,
    rq.Decile,
    rq.HotTagCount,
    rq.IncomingDuplicates,
    rq.HasAccepted,
    -- fetch the top 3 answers for this question as a JSON-ish concatenated string (string functions)
    (select string_agg(format('%s|score=%s|owner=%s', coalesce(substring(a.Title from 1 for 30), '[answer]'), a.Score::text, coalesce(a.OwnerUserId::text,'anon')), '~~' order by a.Score desc nulls last)
     from Posts a where a.ParentId = rq.QuestionId and a.PostTypeId = 2 limit 3) as Top3AnswersSummary,
    -- latest non-null post history comment relevant to closure or migration (complex predicate)
    (select ph.Comment from PostHistory ph
     where ph.PostId = rq.QuestionId
       and ph.PostHistoryTypeId in (10,11,17,35,36)
       and ph.Comment is not null
     order by ph.CreationDate desc limit 1) as LatestClosureOrMigrationComment,
    -- a correlated subquery to compute median-ish answer creation lag (days) using percentile_disc
    (select percentile_disc(0.5) within group (order by extract(epoch from (a.CreationDate - q.CreationDate))/86400.0)
     from Posts a join Posts q on q.Id = rq.QuestionId and q.PostTypeId = 1
     where a.ParentId = rq.QuestionId and a.PostTypeId = 2) as MedianAnswerLagDays
  from RankedQuestions rq
  where rq.GlobalRank <= 200
  order by rq.CompositeScore desc
)
select
  fc.*,
  -- enrich with owner display name and some heuristics
  u.DisplayName,
  u.Location,
  u.EmailHash,
  -- join tags as array and compute top hot tag if any
  (select array_agg(distinct t.Tag order by tt.AvgViews desc nulls last limit 5) from TagPairs t left join TopTags tt on tt.Tag = t.Tag where t.QuestionId = fc.QuestionId) as TopTagsArray,
  (select tt.Tag from TagPairs t join TopTags tt on tt.Tag = t.Tag where t.QuestionId = fc.QuestionId order by tt.AvgViews desc nulls last limit 1) as HottestTag,
  -- correlate whether any of the top tags are moderator-only (example of boolean set membership)
  exists(select 1 from TagPairs t join Tags tg on tg.TagName = t.Tag where t.QuestionId = fc.QuestionId and tg.IsModeratorOnly = b'1') as HasModOnlyTag
from FinalContext fc
left join Users u on u.Id = fc.OwnerUserId
order by fc.CompositeScore desc, fc.QuestionId asc;