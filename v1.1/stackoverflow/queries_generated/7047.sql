-- {"query": "7047.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2626} 
with recursive TagHierarchy(tag, parent_tag, depth) as (
  -- seed: all tags as their own root (depth 0)
  select t.TagName, null::varchar as parent_tag, 0
  from Tags t
),
QuestionBase as (
  -- questions with normalized tags exploded
  select p.Id as QuestionId,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.FavoriteCount,
         p.Title,
         coalesce(p.Tags, '') as RawTags,
         -- split tags string like "<tag1><tag2>" into array, then each tag trimmed of <>
         unnest(string_to_array(substring(coalesce(p.Tags,''), 2, greatest(length(coalesce(p.Tags,'')) - 2,0)), '><')) as Tag
  from Posts p
  where p.PostTypeId = 1
),
AnswerAgg as (
  -- aggregate stats about answers per question including accepted/owner ratios
  select a.ParentId as QuestionId,
         count(*) filter (where a.Score >= 0) as PosAnswers,
         count(*) filter (where a.Score < 0) as NegAnswers,
         sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as IsAcceptedPresent,
         max(a.Score) as MaxAnswerScore,
         avg(a.Score) as AvgAnswerScore,
         count(distinct a.OwnerUserId) as DistinctAnswerers,
         bool_or(a.OwnerUserId = q.OwnerUserId) as HasOwnerAnswered
  from Posts a
  join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  where a.PostTypeId = 2
  group by a.ParentId
),
UserBadgeDensity as (
  -- per-user badge density: badges per reputation bin and recency weighting
  select u.Id as UserId,
         u.Reputation,
         case
           when u.Reputation >= 100000 then 'A'
           when u.Reputation >= 20000 then 'B'
           when u.Reputation >= 5000 then 'C'
           when u.Reputation >= 1000 then 'D'
           else 'E'
         end as RepBin,
         count(b.Id) as TotalBadges,
         sum(case when b.Class = 1 then 3 when b.Class = 2 then 2 else 1 end) as WeightedBadges,
         -- recency: badges awarded within last year more valuable (exponential decay)
         sum(exp(-extract(epoch from (now() - b.Date)) / (60*60*24*90)) ) as RecentBadgeScore
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation
),
RecentActivity as (
  -- capture recent activity per question combining comments, edits and votes within 90 days
  select q.Id as QuestionId,
         max(ph.CreationDate) filter (where ph.CreationDate > now() - interval '90 days') as LastHistory,
         max(c.CreationDate) filter (where c.CreationDate > now() - interval '90 days') as LastComment,
         max(v.CreationDate) filter (where v.CreationDate > now() - interval '90 days') as LastVote,
         count(distinct ph.Id) filter (where ph.CreationDate > now() - interval '90 days') as RecentRevisions,
         count(distinct c.Id) filter (where c.CreationDate > now() - interval '90 days') as RecentComments,
         count(distinct v.Id) filter (where v.CreationDate > now() - interval '90 days') as RecentVotes
  from Posts q
  left join PostHistory ph on ph.PostId = q.Id
  left join Comments c on c.PostId = q.Id
  left join Votes v on v.PostId = q.Id
  where q.PostTypeId = 1
  group by q.Id
),
TagStats as (
  -- for each tag compute popularity, avg question score, and tag co-occurrence (top 3 co-tags)
  select t.TagName,
         count(q.QuestionId) as QuestionsWithTag,
         avg(q.Score) as AvgQScore,
         avg(q.ViewCount) as AvgQViews,
         sum(case when q.AcceptedAnswerId is not null then 1 else 0 end) as WithAccepted,
         -- correlated subquery for top 3 co-occurring tags
         (select string_agg(co.tag || ':' || co.cnt, ',') from (
            select co_tag as tag, count(*) as cnt
            from (
              select qb.QuestionId, qb.Tag as co_tag
              from QuestionBase qb
              where qb.Tag is not null and qb.Tag <> t.TagName
            ) sub
            join QuestionBase qb2 on qb2.QuestionId = sub.QuestionId and qb2.Tag = t.TagName
            group by co_tag
            order by cnt desc
            limit 3
         ) co) as TopCoTags
  from Tags t
  left join QuestionBase q on q.Tag = t.TagName
  group by t.TagName
),
QuestionEnriched as (
  -- join everything for complex filtering and windowing
  select qb.QuestionId,
         qb.OwnerUserId,
         qb.CreationDate,
         qb.Tag,
         qb.Title,
         qb.Score,
         qb.ViewCount,
         qb.AnswerCount,
         qb.FavoriteCount,
         coalesce(aa.PosAnswers,0) as PosAnswers,
         coalesce(aa.NegAnswers,0) as NegAnswers,
         coalesce(aa.MaxAnswerScore,0) as MaxAnswerScore,
         coalesce(ua.WeightedBadges,0) as OwnerWeightedBadges,
         coalesce(ra.RecentRevisions,0) as RecentRevisions,
         coalesce(ra.RecentComments,0) as RecentComments,
         coalesce(ra.RecentVotes,0) as RecentVotes,
         ts.QuestionsWithTag,
         ts.AvgQScore as TagAvgScore,
         ts.TopCoTags,
         -- complex expression: an engagement index using nonlinear transforms, null-safe math, and string manipulations
         (
           -- base: view & score
           (log(greatest(1, qb.ViewCount)) * 0.4)
           + (sign(qb.Score) * pow(abs(qb.Score) + 1, 0.7) * 0.3)
           + (pow(greatest(0, coalesce(aa.DistinctAnswerers,0)), 0.5) * 0.2)
           + (coalesce(qb.FavoriteCount,0) * 0.1)
         ) * (1 + least(1, greatest(0, coalesce(ra.RecentComments,0) / 10.0)))
         + (coalesce(ua.RecentBadgeScore,0) * 0.05)
         as EngagementIndex
  from QuestionBase qb
  left join Posts q on q.Id = qb.QuestionId
  left join AnswerAgg aa on aa.QuestionId = qb.QuestionId
  left join Users u on u.Id = qb.OwnerUserId
  left join UserBadgeDensity ua on ua.UserId = qb.OwnerUserId
  left join RecentActivity ra on ra.QuestionId = qb.QuestionId
  left join TagStats ts on ts.TagName = qb.Tag
),
RankedQuestions as (
  -- window functions to rank within tag and globally, including percentiles and moving averages
  select qe.*,
         row_number() over (partition by qe.Tag order by qe.EngagementIndex desc, qe.Score desc, qe.ViewCount desc) as TagRank,
         dense_rank() over (order by qe.EngagementIndex desc) as GlobalRank,
         ntile(100) over (order by qe.EngagementIndex desc) as EngagementPercentile,
         avg(qe.EngagementIndex) over (partition by qe.Tag rows between 50 preceding and 50 following) as TagLocalMovingAvg,
         lag(qe.EngagementIndex) over (partition by qe.Tag order by qe.CreationDate) as PrevEngagement,
         lead(qe.EngagementIndex) over (partition by qe.Tag order by qe.CreationDate) as NextEngagement
  from QuestionEnriched qe
),
FilteredTop as (
  -- select "interesting" questions: high engagement but with discrepancies (high views but low answer score OR negative sentiment via negative answers)
  select rq.*
  from RankedQuestions rq
  where rq.EngagementIndex is not null
    and (
      (rq.EngagementIndex > 15 and rq.AnswerCount = 0)
      or (rq.ViewCount > 10000 and rq.MaxAnswerScore < 2)
      or (rq.NegAnswers > rq.PosAnswers and rq.Score < 0)
    )
    and rq.EngagementPercentile >= 90
),
CrossTagSimilarity as (
  -- set operator usage: find other tags sharing top co-tags using INTERSECT/EXCEPT logic simulated via aggregation
  select f.Tag as SourceTag,
         other.TagName as SimilarTag,
         (select count(*) from (
            select unnest(string_to_array(coalesce(ts1.TopCoTags,''), ',')) as t1
         ) a join lateral (
            select unnest(string_to_array(coalesce(ts2.TopCoTags,''), ',')) as t2
         ) b on split_part(a.t1, ':', 1) = split_part(b.t2, ':', 1)
         ) as SharedCoTags
  from TagStats ts1
  join TagStats ts2 on ts1.TagName <> ts2.TagName
  join (select distinct Tag from FilteredTop) f on f.Tag = ts1.TagName
  join TagStats other on other.TagName = ts2.TagName
  where other.TagName <> ts1.TagName
),
FinalSelection as (
  -- combine filtered top questions with similarity data and compute an explanatory compact JSON-ish string
  select ft.QuestionId,
         ft.Title,
         ft.Tag,
         ft.OwnerUserId,
         ft.CreationDate,
         ft.Score,
         ft.ViewCount,
         ft.AnswerCount,
         ft.EngagementIndex,
         ft.TagRank,
         ft.GlobalRank,
         ft.EngagementPercentile,
         coalesce(ct.SharedCoTags,0) as SharedCoTagsWithSimilar,
         ts.TopCoTags,
         -- build a short summary string with null handling and truncation
         left(
           coalesce(ft.Title, '<no title>') || ' | tag=' || coalesce(ft.Tag,'<no-tag>') ||
           ' | EI=' || round(ft.EngagementIndex::numeric,2)::text ||
           ' | VR=' || ft.ViewCount::text ||
           ' | AR=' || ft.AnswerCount::text ||
           ' | TRank=' || ft.TagRank::text
         , 300) as BriefSummary
  from FilteredTop ft
  left join CrossTagSimilarity ct on ct.SourceTag = ft.Tag
  left join TagStats ts on ts.TagName = ft.Tag
)
select fs.*,
       -- attach a dynamic sample of comments (correlated subquery) with complicated null/string logic
       (select string_agg(left(coalesce(c.UserDisplayName, 'anon') || ':' || translate(left(c.Text,140),'\\n\\r',' '), 200), ' ||| ')
        from Comments c
        where c.PostId = fs.QuestionId
        order by c.CreationDate desc
        limit 5
       ) as RecentTopComments,
       -- include a correlated scalar: count of duplicate links (PostLinks LinkTypeId = 3) referencing this question
       (select count(*) from PostLinks pl where pl.RelatedPostId = fs.QuestionId and pl.LinkTypeId = 3) as DuplicateReferences,
       -- include a boolean if owner is high-rep and has recent access
       (select (u.Reputation > 10000 and u.LastAccessDate > now() - interval '180 days') from Users u where u.Id = fs.OwnerUserId) as OwnerHighRepActive
from FinalSelection fs
order by fs.EngagementIndex desc, fs.ViewCount desc
limit 250;