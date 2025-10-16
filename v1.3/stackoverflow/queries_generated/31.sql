-- {"query": "31.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2144} 
with
-- candidate questions with parsed tags and tag count
QuestionBase as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    coalesce(p.ViewCount,0) as ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Tags,
    -- normalize tags to an array-like table using simple string operations
    -- tags are stored like '<tag1><tag2>'
    regexp_split_to_table(substring(coalesce(p.Tags,''),2, greatest(length(coalesce(p.Tags,''))-2,0)), '><') as Tag
  from Posts p
  where p.PostTypeId = 1 -- questions
    and p.CreationDate >= now() - interval '5 years'
),
-- aggregate metrics per question including top answer stats and last activity chain
QuestionAgg as (
  select
    q.Id,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.Tags,
    count(distinct q.Tag) as TagCount,
    -- most recent answer score and id (correlated subquery)
    (select a.Id from Posts a
       where a.ParentId = q.Id and a.PostTypeId = 2
       order by a.Score desc nulls last, a.CreationDate desc
       limit 1) as TopAnswerId,
    (select a.Score from Posts a
       where a.ParentId = q.Id and a.PostTypeId = 2
       order by a.Score desc nulls last, a.CreationDate desc
       limit 1) as TopAnswerScore,
    -- last comment time on question
    (select max(c.CreationDate) from Comments c where c.PostId = q.Id) as LastCommentAt,
    -- last history edit time for this post
    (select max(ph.CreationDate) from PostHistory ph where ph.PostId = q.Id) as LastHistoryAt
  from QuestionBase q
  group by
    q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.Tags
),
-- user metrics including rolling reputation and badge diversity
UserStats as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate as UserCreated,
    u.LastAccessDate,
    u.Location,
    -- badges count by class pivot
    coalesce(sum(case when b.Class = 1 then 1 else 0 end),0) as GoldBadges,
    coalesce(sum(case when b.Class = 2 then 1 else 0 end),0) as SilverBadges,
    coalesce(sum(case when b.Class = 3 then 1 else 0 end),0) as BronzeBadges,
    -- distinct tag-based badges (diversity)
    coalesce(count(distinct case when b.TagBased = 1 then b.Name end),0) as TagBadgeKinds,
    -- rolling window: average reputation of user's peers (users created within +/-30 days)
    (select avg(u2.Reputation) from Users u2
       where u2.CreationDate between u.CreationDate - interval '30 days' and u.CreationDate + interval '30 days'
         and u2.Id <> u.Id) as PeerAvgReputation
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
-- combine question-level and user-level metrics, plus complex joins to compute influence
QuestionUserJoin as (
  select
    qa.*,
    us.DisplayName as OwnerDisplayName,
    us.Reputation as OwnerReputation,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges, us.TagBadgeKinds,
    us.PeerAvgReputation,
    -- compute an influence score with non-linear weights and null-safe math
    (coalesce(qa.Score,0) * 1.5
     + ln(greatest(coalesce(qa.ViewCount,0),1)) * 2.3
     + coalesce(qa.AnswerCount,0) * 4.2
     + coalesce(qa.FavoriteCount,0) * 3.7
     + coalesce(us.Reputation,0) * 0.001
     + coalesce(us.GoldBadges,0) * 2.5
     - coalesce(us.BronzeBadges,0) * 0.4
     + case when qa.TagCount > 3 then 5 else 0 end
    )::numeric(18,6) as InfluenceScore
  from QuestionAgg qa
  left join UserStats us on us.UserId = qa.OwnerUserId
),
-- recent link and duplicate info: how many duplicates/links this question participates in
LinkInfo as (
  select
    q.Id as QuestionId,
    count(pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateCount,
    count(pl.Id) filter (where lt.Name = 'Linked') as LinkedCount,
    max(pl.CreationDate) as LastLinkAt
  from Posts q
  left join PostLinks pl on pl.PostId = q.Id or pl.RelatedPostId = q.Id
  left join LinkTypes lt on lt.Id = pl.LinkTypeId
  where q.PostTypeId = 1
  group by q.Id
),
-- votes breakdown using window functions and set operators for heavy IO
VotesBreakdown as (
  select
    v.PostId,
    sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
    sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
    sum(case when vt.VoteTypeId = 1 then 1 else 0 end) as AcceptedByOriginator,
    count(*) as TotalVotes,
    -- ratio with null-safe division
    case when count(*) = 0 then 0 else round(100.0 * sum(case when vt.Name = 'UpMod' then 1 else 0 end)::numeric / count(*),2) end as UpvotePercent
  from Votes v
  left join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
-- heavy analytical result: top N questions by influence with correlated subqueries for contextual info
TopCandidates as (
  select
    qu.*,
    li.DuplicateCount,
    li.LinkedCount,
    li.LastLinkAt,
    vb.UpVotes, vb.DownVotes, vb.TotalVotes, vb.UpvotePercent,
    -- answer acceptance ratio from answers linked to this question
    (select count(1) filter (where a.Id = q.AcceptedAnswerId) from Posts a where a.ParentId = qu.Id) as HasAccepted,
    -- distribution of answer scores as JSON-like concatenation
    (select string_agg((coalesce(a.Score,0) || ':' || coalesce(a.OwnerUserId,-1))::text, ',' order by a.Score desc nulls last)
       from Posts a where a.ParentId = qu.Id) as AnswerScoreOwners,
    -- time to first answer
    (select min(a.CreationDate - qu.CreationDate) from Posts a where a.ParentId = qu.Id) as TimeToFirstAnswer
  from QuestionUserJoin qu
  left join LinkInfo li on li.QuestionId = qu.Id
  left join VotesBreakdown vb on vb.PostId = qu.Id
)
select
  tc.Id,
  tc.Title,
  tc.OwnerUserId,
  coalesce(tc.OwnerDisplayName, 'anonymous') as OwnerDisplay,
  tc.InfluenceScore,
  tc.Score as QuestionScore,
  tc.ViewCount,
  tc.AnswerCount,
  tc.FavoriteCount,
  tc.TagCount,
  tc.Tags,
  tc.DuplicateCount,
  tc.LinkedCount,
  tc.UpVotes,
  tc.DownVotes,
  tc.TotalVotes,
  tc.UpvotePercent,
  coalesce(tc.HasAccepted,0) as HasAccepted,
  tc.TimeToFirstAnswer,
  tc.AnswerScoreOwners,
  -- rank over influence for final ordering
  rank() over (order by tc.InfluenceScore desc, tc.ViewCount desc) as InfluenceRank,
  -- percentile of influence
  percent_rank() over (order by tc.InfluenceScore) as InfluencePercentile,
  -- synthetic computed field combining activity recency and influence
  (case
     when greatest(extract(epoch from coalesce(tc.LastLinkAt, tc.CreationDate))::bigint,0) = 0 then 0
     else round(tc.InfluenceScore / (1 + least(greatest(extract(epoch from now() - coalesce(tc.LastLinkAt, tc.CreationDate)), 1), 60*60*24*365)::numeric/ (60*60*24) ),6)
   end) as FreshInfluence
from TopCandidates tc
where
  -- complex predicate with null logic and regex on title and tag patterns
  (tc.InfluenceScore > 10
   or (tc.AnswerCount >= 3 and coalesce(tc.UpvotePercent,0) > 60)
   or tc.TagCount >= 5)
  and not (tc.Title ilike '%homework%' or tc.Title ~* '\b(beginners?|newbies?)\b')
  and (
    -- include questions that either have recent comments/histories or high view/score
    coalesce((select max(c.CreationDate) from Comments c where c.PostId = tc.Id), tc.LastHistoryAt, tc.CreationDate) >= now() - interval '2 years'
    or tc.ViewCount > 10000
    or tc.Score >= 50
  )
order by InfluenceRank
limit 250;