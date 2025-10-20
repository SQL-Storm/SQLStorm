-- {"query": "38043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2344} 
with recent_questions as (
  select p.Id as QuestionId,
         p.CreationDate,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.Title,
         p.Tags,
         p.AnswerCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '180 days' from Posts where PostTypeId = 1)
),
answers as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswererId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreationDate
  from Posts a
  where a.PostTypeId = 2
),
first_answer as (
  select QuestionId,
         min(AnswerCreationDate) as FirstAnswerDate
  from answers
  group by QuestionId
),
votes_agg as (
  select v.PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
         sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyAmount
  from Votes v
  group by v.PostId
),
comments_agg as (
  select c.PostId,
         count(*) as CommentCount,
         max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
accepted as (
  select q.Id as QuestionId,
         q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1
),
postlinks_dupes as (
  select pl.PostId as DuplicateId,
         pl.RelatedPostId as CanonicalId,
         count(*) filter (where pl.LinkTypeId = 3) as DupCount
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId, pl.RelatedPostId
),
tags_expanded as (
  select p.Id as QuestionId,
         unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag
  from Posts p
  where p.PostTypeId = 1
    and p.Tags is not null
),
tag_popularity as (
  select te.tag,
         count(*) as TagQuestionCount,
         avg(p.Score) as AvgTagScore
  from tags_expanded te
  join Posts p on p.Id = te.QuestionId
  group by te.tag
),
user_stats as (
  select u.Id as UserId,
         u.Reputation,
         u.CreationDate,
         u.UpVotes,
         u.DownVotes,
         coalesce(b_gold.GoldCount,0) as GoldBadges,
         coalesce(b_silver.SilverCount,0) as SilverBadges,
         coalesce(b_bronze.BronzeCount,0) as BronzeBadges
  from Users u
  left join (
    select UserId, count(*) as GoldCount
    from Badges
    where Class = 1
    group by UserId
  ) b_gold on b_gold.UserId = u.Id
  left join (
    select UserId, count(*) as SilverCount
    from Badges
    where Class = 2
    group by UserId
  ) b_silver on b_silver.UserId = u.Id
  left join (
    select UserId, count(*) as BronzeCount
    from Badges
    where Class = 3
    group by UserId
  ) b_bronze on b_bronze.UserId = u.Id
),
edit_activity as (
  select ph.PostId,
         count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditCount,
         max(ph.CreationDate) as LastEditDate,
         count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20)) as ModActionCount
  from PostHistory ph
  group by ph.PostId
),
question_metrics as (
  select rq.QuestionId,
         rq.Title,
         rq.CreationDate,
         rq.OwnerUserId,
         rq.Score as QuestionScore,
         rq.ViewCount,
         rq.AnswerCount,
         va.UpVotes as QUpVotes,
         va.DownVotes as QDownVotes,
         va.Favorites as QFavorites,
         va.BountyAmount as QBountyAmount,
         ca.CommentCount as QCommentCount,
         ca.LastCommentDate as QLastCommentDate,
         ea.EditCount as QEditCount,
         ea.LastEditDate as QLastEditDate,
         ea.ModActionCount as QModActionCount,
         fa.FirstAnswerDate,
         extract(epoch from (fa.FirstAnswerDate - rq.CreationDate)) / 3600.0 as HoursToFirstAnswer,
         case when ac.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
         pd.DupCount as DuplicateLinksCount
  from recent_questions rq
  left join votes_agg va on va.PostId = rq.QuestionId
  left join comments_agg ca on ca.PostId = rq.QuestionId
  left join edit_activity ea on ea.PostId = rq.QuestionId
  left join first_answer fa on fa.QuestionId = rq.QuestionId
  left join accepted ac on ac.QuestionId = rq.QuestionId
  left join postlinks_dupes pd on pd.DuplicateId = rq.QuestionId
),
answer_metrics as (
  select a.QuestionId,
         count(*) as AnswerTotal,
         avg(a.AnswerScore) as AvgAnswerScore,
         max(a.AnswerScore) as MaxAnswerScore,
         min(a.AnswerScore) as MinAnswerScore,
         sum(case when a.AnswerScore > 0 then 1 else 0 end) as PositiveAnswers,
         sum(case when a.AnswerScore < 0 then 1 else 0 end) as NegativeAnswers
  from answers a
  group by a.QuestionId
),
tag_rollup as (
  select te.QuestionId,
         array_agg(te.tag order by te.tag) as TagsArray
  from tags_expanded te
  group by te.QuestionId
),
owner_enriched as (
  select qm.*,
         us.Reputation as OwnerReputation,
         us.GoldBadges,
         us.SilverBadges,
         us.BronzeBadges
  from question_metrics qm
  left join user_stats us on us.UserId = qm.OwnerUserId
),
final_scored as (
  select oe.QuestionId,
         oe.Title,
         oe.CreationDate,
         oe.OwnerUserId,
         oe.OwnerReputation,
         oe.GoldBadges,
         oe.SilverBadges,
         oe.BronzeBadges,
         oe.QuestionScore,
         oe.QUpVotes,
         oe.QDownVotes,
         oe.QFavorites,
         oe.QBountyAmount,
         oe.ViewCount,
         oe.AnswerCount,
         am.AnswerTotal,
         am.AvgAnswerScore,
         am.MaxAnswerScore,
         am.MinAnswerScore,
         am.PositiveAnswers,
         am.NegativeAnswers,
         oe.QCommentCount,
         oe.QLastCommentDate,
         oe.QEditCount,
         oe.QLastEditDate,
         oe.QModActionCount,
         oe.FirstAnswerDate,
         oe.HoursToFirstAnswer,
         oe.HasAcceptedAnswer,
         coalesce(oe.DuplicateLinksCount,0) as DuplicateLinksCount,
         tr.TagsArray,
         -- Composite performance-heavy score combining multiple aggregates
         (
           coalesce(oe.QuestionScore,0)*2
           + coalesce(oe.QUpVotes,0)*1.5
           - coalesce(oe.QDownVotes,0)*1.0
           + coalesce(oe.QFavorites,0)*0.5
           + coalesce(oe.QBountyAmount,0)/100.0
           + coalesce(am.AvgAnswerScore,0)*1.2
           + coalesce(am.PositiveAnswers,0)*0.8
           - coalesce(am.NegativeAnswers,0)*0.6
           + case when oe.HasAcceptedAnswer=1 then 5 else 0 end
           - least(coalesce(oe.HoursToFirstAnswer, 24.0)/24.0, 10)
           + ln(1 + coalesce(oe.ViewCount,0))
           + coalesce(oe.OwnerReputation,0)/1000.0
           + coalesce(oe.GoldBadges,0)*0.5
           + coalesce(oe.SilverBadges,0)*0.2
           + coalesce(oe.BronzeBadges,0)*0.1
           - coalesce(oe.DuplicateLinksCount,0)*2
           - coalesce(oe.QModActionCount,0)*0.3
         ) as CompositeScore
  from owner_enriched oe
  left join answer_metrics am on am.QuestionId = oe.QuestionId
  left join tag_rollup tr on tr.QuestionId = oe.QuestionId
),
ranked as (
  select fs.*,
         row_number() over (order by fs.CompositeScore desc, fs.ViewCount desc, fs.CreationDate desc) as rn,
         ntile(10) over (order by fs.CompositeScore desc) as decile,
         avg(fs.CompositeScore) over () as GlobalAvgScore,
         percentile_cont(0.9) within group (order by fs.CompositeScore) over () as P90Score
  from final_scored fs
)
select r.QuestionId,
       r.Title,
       r.CreationDate,
       r.OwnerUserId,
       r.OwnerReputation,
       r.GoldBadges,
       r.SilverBadges,
       r.BronzeBadges,
       r.QuestionScore,
       r.QUpVotes,
       r.QDownVotes,
       r.QFavorites,
       r.QBountyAmount,
       r.ViewCount,
       r.AnswerCount,
       r.AnswerTotal,
       r.AvgAnswerScore,
       r.MaxAnswerScore,
       r.MinAnswerScore,
       r.PositiveAnswers,
       r.NegativeAnswers,
       r.QCommentCount,
       r.QLastCommentDate,
       r.QEditCount,
       r.QLastEditDate,
       r.QModActionCount,
       r.FirstAnswerDate,
       r.HoursToFirstAnswer,
       r.HasAcceptedAnswer,
       r.DuplicateLinksCount,
       r.TagsArray,
       r.CompositeScore,
       r.decile,
       r.GlobalAvgScore,
       r.P90Score
from ranked r
where r.rn <= 200
order by r.CompositeScore desc, r.ViewCount desc, r.CreationDate desc;