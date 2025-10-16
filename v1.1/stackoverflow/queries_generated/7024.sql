-- {"query": "7024.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2503} 
with
-- recent active questions with parsed tag array and tag count
RecentQuestions as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    coalesce(nullif(p.Tags, ''), '') as RawTags,
    case when p.Tags is null then array[]::varchar[] else string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') end as TagArray,
    -- synthetic complexity: length of title * score with null-safe math
    coalesce(p.Score,0) * greatest(length(coalesce(p.Title,'')),1) as TitleScoreProduct
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '2 years'
    and (p.Score is not null and p.Score >= -5)
),
-- answers enriched with owner and parent question stats
AnswerAug as (
  select
    a.Id,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.CreationDate,
    a.Score,
    a.CommentCount,
    a.Body,
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate) as RankByScore,
    dense_rank() over (partition by a.ParentId order by a.Score desc nulls last) as DenseRankByScore,
    sum(coalesce(vote_counts.up,0)) over (partition by a.ParentId) as TotalUpVotesOnQuestionAnswers
  from Posts a
  left join lateral (
    select
      sum(case when v.VoteTypeId = 2 then 1 else 0 end) as up,
      sum(case when v.VoteTypeId = 3 then 1 else 0 end) as down
    from Votes v
    where v.PostId = a.Id
  ) vote_counts on true
  where a.PostTypeId = 2
),
-- per-question aggregated vote stats and most recent comment
QuestionStats as (
  select
    q.Id,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.TagArray,
    count(distinct a.Id) filter (where a.Id is not null) as AnswersReported,
    sum(coalesce(av.up,0)) as SumAnswerUpVotes,
    sum(coalesce(av.down,0)) as SumAnswerDownVotes,
    max(a.CreationDate) as LatestAnswerDate,
    (select c.Text from Comments c where c.PostId = q.Id order by c.CreationDate desc limit 1) as LatestQuestionComment,
    -- correlated subquery: one-line sentiment-ish measure from PostHistory edits containing keywords
    (
      select count(*) from PostHistory ph
      where ph.PostId = q.Id
        and ph.PostHistoryTypeId in (5,2,8,3,6) -- body/title/tags edits
        and (ph.Text ilike '%fix%' or ph.Text ilike '%typo%' or ph.Text ilike '%clarif%')
    ) as EditFixCount
  from RecentQuestions q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join lateral (
    select
      sum(case when v.VoteTypeId = 2 then 1 else 0 end) as up,
      sum(case when v.VoteTypeId = 3 then 1 else 0 end) as down
    from Votes v
    where v.PostId = a.Id
  ) av on true
  group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.TagArray
),
-- user-level aggregates combining badges, reputation, activity and answering behavior
UserProfile as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    -- time since creation in days (float)
    extract(epoch from (now() - u.CreationDate))/86400.0 as DaysSinceSignup,
    -- average score of user's answers (correlated subquery)
    (
      select avg(coalesce(a.Score,0)) from Posts a where a.OwnerUserId = u.Id and a.PostTypeId = 2
    ) as AvgAnswerScore,
    -- recent activity measure: counts of posts/comments in last 90 days
    (
      select count(*) from Posts p2 where p2.OwnerUserId = u.Id and p2.CreationDate >= now() - interval '90 days'
    ) as RecentPosts90,
    (
      select count(*) from Comments c2 where c2.UserId = u.Id and c2.CreationDate >= now() - interval '90 days'
    ) as RecentComments90
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
-- hot tag scoring by combining tag popularity, recency, diversity of answerers
TagSignals as (
  select
    tg.tag,
    sum(q.Score) as SumScore,
    count(distinct q.Id) as QuestionCount,
    avg(q.AnswerCount) as AvgAnswers,
    max(q.ViewCount) as MaxViews,
    -- diversity: count distinct answer owners across recent questions for the tag
    (
      select count(distinct a.OwnerUserId) from Posts a
      where a.PostTypeId = 2
        and exists (
          select 1 from RecentQuestions rq
          where rq.Id = a.ParentId
            and rq.TagArray @> array[tg.tag]
        )
    ) as AnswererDiversity
  from RecentQuestions q
  cross join lateral unnest(q.TagArray) as tg(tag)
  group by tg.tag
),
-- complex union to exercise set operators and null logic: combine candidate questions with and without accepted answers
CandidateUnion as (
  select
    qs.*,
    up.DisplayName as QuestionOwner,
    up.Reputation as OwnerReputation,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    case when qs.AnswersReported = 0 then 'unanswered' else 'answered' end as AnswerStatus,
    null::int as AcceptedAnswerId,
    null::int as AcceptedAnswerScore
  from QuestionStats qs
  left join UserProfile up on up.UserId = qs.OwnerUserId
  where qs.AnswersReported = 0

  union

  select
    qs.*,
    up.DisplayName as QuestionOwner,
    up.Reputation as OwnerReputation,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    'accepted' as AnswerStatus,
    p.AcceptedAnswerId,
    (select a.Score from Posts a where a.Id = p.AcceptedAnswerId) as AcceptedAnswerScore
  from QuestionStats qs
  join Posts p on p.Id = qs.Id
  left join UserProfile up on up.UserId = qs.OwnerUserId
  where p.AcceptedAnswerId is not null

  union

  -- low scored but highly viewed questions to catch anomalies
  select
    qs.*,
    up.DisplayName as QuestionOwner,
    up.Reputation as OwnerReputation,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    'popular-low-score' as AnswerStatus,
    null::int,
    null::int
  from QuestionStats qs
  left join UserProfile up on up.UserId = qs.OwnerUserId
  where qs.ViewCount > 10000 and coalesce(qs.Score,0) < 1
),
-- final assembly with window functions, complicated predicates and string expressions
FinalRanked as (
  select
    cu.Id as QuestionId,
    cu.Title,
    cu.TagArray,
    cu.TitleScoreProduct,
    cu.AnswersReported,
    cu.EditFixCount,
    cu.LatestQuestionComment,
    cu.LatestAnswerDate,
    cu.AnswerStatus,
    cu.AcceptedAnswerId,
    cu.AcceptedAnswerScore,
    cu.QuestionOwner,
    cu.OwnerReputation,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    -- combine multiple signals into scoring expression with null-safe coalesce and conditional weightings
    (
      -- base from viewcount and score
      (coalesce(cu.ViewCount,0) * 0.001)
      + (coalesce(cu.Score,0) * 2.5)
      + (coalesce(cu.AnswersReported,0) * 3.0)
      + (coalesce(cu.EditFixCount,0) * 1.2)
      + case when cu.AcceptedAnswerId is not null then 10 else 0 end
      + case when cu.AnswerStatus = 'unanswered' then -5 else 0 end
      - (CASE WHEN cu.LatestAnswerDate IS NULL THEN 0 ELSE greatest(0, extract(epoch from (now() - cu.LatestAnswerDate))/86400.0) * 0.01 END)
    ) as CompositeHotness,
    -- tag string: comma separated with truncation, show top 3
    ( select string_agg(t,',' order by t) from (select unnest(cu.TagArray) t limit 3) s ) as TopTags,
    row_number() over (order by (
      (coalesce(cu.ViewCount,0) * 0.001)
      + (coalesce(cu.Score,0) * 2.5)
      + (coalesce(cu.AnswersReported,0) * 3.0)
      + (case when cu.AcceptedAnswerId is not null then 10 else 0 end)
    ) desc nulls last, cu.EditFixCount desc) as GlobalRank,
    dense_rank() over (partition by cu.AnswerStatus order by coalesce(cu.ViewCount,0) desc) as RankWithinStatus,
    -- a correlated existence check: does any answer on this question have a score greater than owner's reputation / 10?
    exists (
      select 1 from Posts a where a.ParentId = cu.Id and a.PostTypeId = 2 and coalesce(a.Score,0) > coalesce(cu.OwnerReputation,0)/10.0
    ) as HasHighScoringAnswerRelativeToOwner
  from CandidateUnion cu
)
select
  f.QuestionId,
  left(f.Title,200) as Title,
  f.TopTags,
  f.AnswersReported,
  f.EditFixCount,
  f.LatestQuestionComment,
  f.AnswerStatus,
  f.AcceptedAnswerId,
  f.AcceptedAnswerScore,
  f.QuestionOwner,
  f.OwnerReputation,
  f.GoldBadges,
  f.SilverBadges,
  f.BronzeBadges,
  round(f.CompositeHotness::numeric,3) as CompositeHotness,
  f.GlobalRank,
  f.RankWithinStatus,
  f.HasHighScoringAnswerRelativeToOwner
from FinalRanked f
where f.CompositeHotness is not null
order by f.CompositeHotness desc nulls last, f.GlobalRank
limit 250;