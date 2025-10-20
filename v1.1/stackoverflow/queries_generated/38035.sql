-- {"query": "38035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2103} 
with recent_q as (
  select p.Id as QuestionId,
         p.CreationDate as QuestionCreated,
         p.Score as QuestionScore,
         p.ViewCount,
         p.OwnerUserId as AskerId,
         p.Tags,
         coalesce(p.AnswerCount,0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
),
answers as (
  select a.ParentId as QuestionId,
         a.Id as AnswerId,
         a.OwnerUserId as AnswererId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreated
  from Posts a
  where a.PostTypeId = 2
),
accepted as (
  select q.Id as QuestionId, q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
 first_answer as (
  select a.QuestionId,
         min(a.AnswerCreated) as FirstAnswerTime
  from answers a
  group by a.QuestionId
),
votes_agg as (
  select v.PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
         sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountySum,
         min(v.CreationDate) as FirstVoteAt,
         max(v.CreationDate) as LastVoteAt
  from Votes v
  group by v.PostId
),
comments_agg as (
  select c.PostId,
         count(*) as CommentCount,
         max(c.Score) as MaxCommentScore,
         max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
 link_dupes as (
  select pl.PostId as QuestionId,
         count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
         count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks
  from PostLinks pl
  group by pl.PostId
),
 close_events as (
  select ph.PostId as QuestionId,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosedAt,
         max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenedAt,
         count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesEvents,
         count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11)
  group by ph.PostId
),
 tag_expanded as (
  select rq.QuestionId,
         unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) as TagName
  from recent_q rq
  where rq.Tags is not null and rq.Tags like '<%>'
),
 tag_stats as (
  select te.QuestionId,
         count(*) as TagCount,
         max(t.Count) as MaxGlobalTagCount,
         sum(t.Count) as SumGlobalTagCount
  from tag_expanded te
  left join Tags t on t.TagName = te.TagName
  group by te.QuestionId
),
 user_stats as (
  select u.Id as UserId,
         u.Reputation,
         u.CreationDate as UserCreated,
         u.Views as ProfileViews,
         u.UpVotes as GivenUpVotes,
         u.DownVotes as GivenDownVotes
  from Users u
),
 qa_join as (
  select rq.*,
         ua.Reputation as AskerReputation,
         ua.ProfileViews as AskerProfileViews,
         ua.GivenUpVotes as AskerGivenUpVotes,
         ua.GivenDownVotes as AskerGivenDownVotes,
         fa.FirstAnswerTime,
         ce.FirstClosedAt,
         ce.LastReopenedAt,
         ce.CloseVotesEvents,
         ce.ReopenEvents,
         coalesce(va.UpVotes,0) as QUpVotes,
         coalesce(va.DownVotes,0) as QDownVotes,
         coalesce(va.Favorites,0) as QFavorites,
         coalesce(va.BountySum,0) as QBountySum,
         va.FirstVoteAt as QFirstVoteAt,
         va.LastVoteAt as QLastVoteAt,
         coalesce(ca.CommentCount,0) as QCommentCount,
         ca.MaxCommentScore as QMaxCommentScore,
         ca.LastCommentAt as QLastCommentAt,
         coalesce(ld.DuplicateLinks,0) as DuplicateLinks,
         coalesce(ld.LinkedLinks,0) as LinkedLinks,
         ts.TagCount,
         ts.MaxGlobalTagCount,
         ts.SumGlobalTagCount
  from recent_q rq
  left join user_stats ua on ua.UserId = rq.AskerId
  left join first_answer fa on fa.QuestionId = rq.QuestionId
  left join close_events ce on ce.QuestionId = rq.QuestionId
  left join votes_agg va on va.PostId = rq.QuestionId
  left join comments_agg ca on ca.PostId = rq.QuestionId
  left join link_dupes ld on ld.QuestionId = rq.QuestionId
  left join tag_stats ts on ts.QuestionId = rq.QuestionId
),
 answer_rollup as (
  select a.QuestionId,
         count(*) as AnswersTotal,
         count(*) filter (where a.Score > 0) as AnswersPositive,
         count(*) filter (where a.Score <= 0) as AnswersNonPositive,
         max(a.Score) as MaxAnswerScore,
         min(a.CreationDate) as FirstAnswerCreated,
         max(a.CreationDate) as LastAnswerCreated,
         count(distinct a.AnswererId) as DistinctAnswerers
  from answers a
  group by a.QuestionId
),
 accepted_mark as (
  select ac.QuestionId,
         1 as HasAccepted
  from accepted ac
),
 speed_buckets as (
  select qj.QuestionId,
         case
           when qj.FirstAnswerTime is null then 'no-answer'
           when qj.FirstAnswerTime <= qj.QuestionCreated + interval '1 hour' then 'within-1h'
           when qj.FirstAnswerTime <= qj.QuestionCreated + interval '1 day' then 'within-1d'
           when qj.FirstAnswerTime <= qj.QuestionCreated + interval '7 days' then 'within-7d'
           else 'after-7d'
         end as FirstAnswerBucket
  from qa_join qj
),
 hotness as (
  select qj.QuestionId,
         (coalesce(qj.QUpVotes,0) - coalesce(qj.QDownVotes,0)) * 2
         + coalesce(qj.QFavorites,0)
         + least(coalesce(qj.ViewCount,0)/100, 500)
         + case when qj.FirstAnswerTime is not null then 50 else 0 end
         - case when qj.FirstClosedAt is not null then 100 else 0 end
         + coalesce(qj.TagCount,0) * 5
         as HotnessScore
  from qa_join qj
),
 final as (
  select
    qj.QuestionId,
    qj.QuestionCreated,
    qj.QuestionScore,
    qj.ViewCount,
    qj.AnswerCount,
    ar.AnswersTotal,
    ar.AnswersPositive,
    ar.AnswersNonPositive,
    ar.MaxAnswerScore,
    ar.FirstAnswerCreated,
    ar.LastAnswerCreated,
    sm.FirstAnswerBucket,
    coalesce(am.HasAccepted,0) as HasAccepted,
    qj.AskerId,
    qj.AskerReputation,
    qj.AskerProfileViews,
    qj.AskerGivenUpVotes,
    qj.AskerGivenDownVotes,
    qj.TagCount,
    qj.MaxGlobalTagCount,
    qj.SumGlobalTagCount,
    qj.QUpVotes,
    qj.QDownVotes,
    qj.QFavorites,
    qj.QBountySum,
    qj.QFirstVoteAt,
    qj.QLastVoteAt,
    qj.QCommentCount,
    qj.QMaxCommentScore,
    qj.QLastCommentAt,
    qj.DuplicateLinks,
    qj.LinkedLinks,
    qj.FirstClosedAt,
    qj.LastReopenedAt,
    qj.CloseVotesEvents,
    qj.ReopenEvents,
    h.HotnessScore
  from qa_join qj
  left join answer_rollup ar on ar.QuestionId = qj.QuestionId
  left join accepted_mark am on am.QuestionId = qj.QuestionId
  left join speed_buckets sm on sm.QuestionId = qj.QuestionId
  left join hotness h on h.QuestionId = qj.QuestionId
)
select
  f.*,
  rank() over (order by f.HotnessScore desc nulls last) as HotnessRank,
  percentile_disc(0.5) within group (order by coalesce(f.QUpVotes - f.QDownVotes,0)) over () as GlobalScoreMedian,
  avg(f.AnswersTotal) over () as AvgAnswersTotal,
  avg(f.QCommentCount) over () as AvgCommentsPerQ,
  count(*) over () as SampleSize
from final f
where coalesce(f.ViewCount,0) > 0
  and f.QuestionScore is not null
order by f.HotnessScore desc nulls last, f.ViewCount desc
limit 500;