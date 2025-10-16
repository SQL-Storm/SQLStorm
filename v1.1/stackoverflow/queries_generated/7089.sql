-- {"query": "7089.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2282} 
with
-- popular questions and derived tag array
QuestionBase as (
  select p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
         coalesce(p.AnswerCount,0) as AnswerCount,
         regexp_split_to_array(trim(both '<>' from coalesce(p.Tags,'')), E'><') as TagArray,
         p.AcceptedAnswerId
  from Posts p
  where p.PostTypeId = 1
),
-- recent activity windowed metrics per question
QuestionMetrics as (
  select qb.*,
         row_number() over (order by qb.Score desc, qb.ViewCount desc) as GlobalRank,
         rank() over (partition by date_trunc('month', qb.CreationDate) order by qb.Score desc) as MonthlyScoreRank,
         sum(coalesce(vt_up.upvotes,0)) over (partition by qb.Id) as TotalUpVotes,
         sum(coalesce(vt_down.downvotes,0)) over (partition by qb.Id) as TotalDownVotes,
         -- ratio with null-safe math
         case when coalesce(sum(coalesce(vt_down.downvotes,0)) over (partition by qb.Id),0)=0
              then null
              else round(1.0 * sum(coalesce(vt_up.upvotes,0)) over (partition by qb.Id) / sum(coalesce(vt_down.downvotes,0)) over (partition by qb.Id),3)
         end as UpDownRatio
  from QuestionBase qb
  left join (
    select v.PostId, count(*) as upvotes
    from Votes v
    where v.VoteTypeId = 2
    group by v.PostId
  ) vt_up on vt_up.PostId = qb.Id
  left join (
    select v.PostId, count(*) as downvotes
    from Votes v
    where v.VoteTypeId = 3
    group by v.PostId
  ) vt_down on vt_down.PostId = qb.Id
),
-- compute per-user aggregated contributions and stringified tag-list
UserAggregates as (
  select u.Id as UserId, u.DisplayName, u.Reputation,
         count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionsAsked,
         count(distinct p.Id) filter (where p.PostTypeId=2) as AnswersGiven,
         count(distinct b.Id) as BadgesCount,
         string_agg(distinct t.TagName, ',' order by max(p.CreationDate) desc) as TagsTouched,
         max(u.CreationDate) as UserSince,
         -- active score: weighted metric
         coalesce(0.6*count(distinct p.Id) filter (where p.PostTypeId=2) + 0.4*count(distinct p.Id) filter (where p.PostTypeId=1) + 0.01*coalesce(sum(v.BountyAmount),0),0) as ActivityScore
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Badges b on b.UserId = u.Id
  left join Tags t on t.ExcerptPostId = p.Id or t.WikiPostId = p.Id
  left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9)
  group by u.Id, u.DisplayName, u.Reputation
),
-- top linked posts (both directions), complex set operators to union duplicates and links
LinkedPairs as (
  select pl.PostId, pl.RelatedPostId, lt.Name as LinkType, pl.CreationDate
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  where pl.PostId is not null and pl.RelatedPostId is not null

  union

  -- symmetric view (invert)
  select pl.RelatedPostId as PostId, pl.PostId as RelatedPostId, lt.Name as LinkType, pl.CreationDate
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
),
-- CTE to find question neighborhoods with correlated subqueries for recent edits and comment counts
Neighborhood as (
  select q.Id as QuestionId, q.Title, q.CreationDate, q.Score as QScore,
         q.AcceptedAnswerId,
         qa.Id as AnswerId, qa.OwnerUserId as AnswerOwner, qa.Score as AnswerScore,
         -- correlated subquery for last editor on answer
         (select ph.UserId
          from PostHistory ph
          where ph.PostId = qa.Id and ph.PostHistoryTypeId in (4,5,24)
          order by ph.CreationDate desc
          limit 1) as LastEditorUserId,
         -- count of comments for question and answer
         (select count(*) from Comments c where c.PostId = q.Id) as QComments,
         (select count(*) from Comments c where c.PostId = qa.Id) as AComments
  from Posts q
  left join Posts qa on qa.ParentId = q.Id and qa.PostTypeId = 2
  where q.PostTypeId = 1
),
-- rank answers per question using window functions and string expressions
AnswerRanks as (
  select n.*,
         dense_rank() over (partition by n.QuestionId order by n.AnswerScore desc nulls last) as AnswerRank,
         -- build a compact provenance string
         concat('Q:', n.QuestionId, '|A:', coalesce(n.AnswerId,'-'), '|AScore:', coalesce(n.AnswerScore,0), '|CmtQ:', coalesce(n.QComments,0), '|CmtA:', coalesce(n.AComments,0)) as Provenance
  from Neighborhood n
),
-- pick canonical sample set: top N questions by combined metric with complicated predicate
SampleQuestions as (
  select qm.*
  from QuestionMetrics qm
  where
    -- require reasonably popular and non-trivial
    qm.ViewCount >= 100 and qm.Score >= 5
    and qm.AnswerCount >= 2
    and (qm.TotalUpVotes is null or qm.TotalUpVotes >= greatest(5, qm.Score))
    and (
      -- favor questions touching more than one tag; TagArray length calc with null-safe handling
      case when qm.TagArray is null then 0 else array_length(qm.TagArray,1) end >= 2
      or qm.GlobalRank <= 100
    )
  order by qm.GlobalRank
  limit 250
),
-- expand tag counts and compute tag popularity across sample questions
SampleTags as (
  select sq.Id as QuestionId, unnest(sq.TagArray) as Tag
  from SampleQuestions sq
),
TagPopularity as (
  select st.Tag,
         count(distinct st.QuestionId) as QuestionsInSample,
         coalesce(sum(q.Score),0) as CumScore
  from SampleTags st
  join Posts q on q.Id = st.QuestionId
  group by st.Tag
  order by QuestionsInSample desc
  limit 100
),
-- final assembly: join everything and compute heavy expressions, outer joins to include nulls
Final as (
  select sq.Id as QuestionId,
         sq.Title,
         sq.CreationDate as QuestionCreated,
         sq.Score as QuestionScore,
         sq.ViewCount,
         sq.AnswerCount,
         sq.GlobalRank,
         sq.MonthlyScoreRank,
         ua.UserId as OwnerId,
         ua.DisplayName as OwnerName,
         ua.Reputation as OwnerReputation,
         ua.BadgesCount,
         ua.TagsTouched,
         tp.Tag as SampleTag,
         tp.QuestionsInSample,
         tp.CumScore,
         -- correlated scalar subquery: latest activity timestamp among answers/comments/votes
         greatest(
           sq.CreationDate,
           coalesce((select max(LastEditDate) from Posts p2 where p2.ParentId = sq.Id), sq.CreationDate),
           coalesce((select max(CreationDate) from Comments c where c.PostId = sq.Id), sq.CreationDate),
           coalesce((select max(CreationDate) from Votes v where v.PostId = sq.Id), sq.CreationDate)
         ) as LatestActivity,
         -- complex CASE with null logic and math
         case
           when sq.AnswerCount = 0 then null
           when sq.AnswerCount > 0 and coalesce(sq.AcceptedAnswerId,0) > 0 then 1.0
           else round( (1.0 * sq.Score) / nullif(greatest(1, sqrt(sq.ViewCount::numeric)), 0), 4)
         end as QualitySignal,
         -- assemble a compact diagnostic string using nested functions and null handling
         concat_ws(' | ',
           concat('Owner:[', coalesce(ua.DisplayName,'<anon>'), '#', ua.UserId, ']'),
           concat('QScore=', sq.Score, ',V=', sq.ViewCount),
           concat('Ranks(G/M)=', sq.GlobalRank, '/', coalesce(sq.MonthlyScoreRank,'-')),
           concat('Tags=', array_to_string(coalesce(sq.TagArray,array[]::text[]),','))
         ) as Diagnostic,
         -- include top 3 answers provenance as JSON-ish string using subquery with string_agg
         (select string_agg(ar.Provenance, ' || ')
          from (
            select concat('AId:', coalesce(a.Id::text,'-'),
                          ',S:', coalesce(a.Score::text,'0'),
                          ',U:', coalesce(a.OwnerUserId::text,'-'),
                          ',C:', coalesce((select count(*) from Comments c where c.PostId = a.Id)::text,'0')
                         ) as Provenance, row_number() over () as rn
            from Posts a
            where a.ParentId = sq.Id and a.PostTypeId = 2
            order by a.Score desc nulls last
            limit 3
          ) ar
         ) as Top3AnswersSummary,
         -- indicator if question has duplicate links (LinkType = 'Duplicate')
         exists (select 1 from LinkedPairs lp where lp.PostId = sq.Id and lower(lp.LinkType) like '%duplicate%') as HasDuplicateLink,
         -- sample user activity score for owner (coalesced)
         coalesce(ua.ActivityScore,0) as OwnerActivityScore
  from SampleQuestions sq
  left join Users u on u.Id = sq.OwnerUserId
  left join UserAggregates ua on ua.UserId = u.Id
  left join SampleTags st on st.QuestionId = sq.Id
  left join TagPopularity tp on tp.Tag = st.Tag
)
select *
from Final
order by OwnerActivityScore desc nulls last, QuestionScore desc
limit 200;