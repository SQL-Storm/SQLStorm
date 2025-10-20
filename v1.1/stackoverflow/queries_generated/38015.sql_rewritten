-- {"query": "38015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2451} 
with recent_questions as (
  select p.Id as QuestionId,
         p.CreationDate as QuestionCreationDate,
         p.Score as QuestionScore,
         p.ViewCount,
         p.OwnerUserId as AskerId,
         p.Tags,
         p.Title
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select date_trunc('month', max(CreationDate)) - interval '6 months' from Posts where PostTypeId = 1)
), answers as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswererId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreationDate,
         a.LastActivityDate
  from Posts a
  where a.PostTypeId = 2
), first_answer as (
  select a.QuestionId,
         min(a.AnswerCreationDate) as FirstAnswerDate
  from answers a
  group by a.QuestionId
), votes_by_type as (
  select v.PostId,
         v.VoteTypeId,
         count(*) as VoteCount,
         sum(coalesce(v.BountyAmount,0)) as TotalBounty
  from Votes v
  group by v.PostId, v.VoteTypeId
), agg_question_votes as (
  select PostId,
         sum(case when VoteTypeId = 2 then VoteCount else 0 end) as UpVotes,
         sum(case when VoteTypeId = 3 then VoteCount else 0 end) as DownVotes,
         sum(case when VoteTypeId = 8 then VoteCount else 0 end) as BountyStarts,
         sum(case when VoteTypeId = 9 then VoteCount else 0 end) as BountyCloses,
         sum(case when VoteTypeId = 9 then TotalBounty else 0 end) as BountyAwarded
  from votes_by_type
  group by PostId
), comments_agg as (
  select c.PostId,
         count(*) as CommentCount,
         max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
), tag_expansion as (
  select q.QuestionId,
         unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag
  from recent_questions q
  where q.Tags is not null and q.Tags <> ''
), tag_top as (
  select te.tag,
         count(*) as QuestionCount,
         row_number() over (order by count(*) desc) as rn
  from tag_expansion te
  group by te.tag
), top_tags as (
  select tag
  from tag_top
  where rn <= 50
), user_stats as (
  select u.Id as UserId,
         u.Reputation,
         u.CreationDate as UserCreationDate,
         u.Views as ProfileViews,
         u.UpVotes as GivenUpVotes,
         u.DownVotes as GivenDownVotes
  from Users u
), badge_agg as (
  select b.UserId,
         sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
         sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
         sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
         count(*) as TotalBadges,
         max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
), accepted_map as (
  select q.Id as QuestionId, q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
), qa_join as (
  select rq.QuestionId,
         rq.QuestionCreationDate,
         rq.QuestionScore,
         rq.ViewCount,
         rq.AskerId,
         rq.Title,
         rq.Tags,
         fa.FirstAnswerDate,
         am.AcceptedAnswerId,
         extract(epoch from (fa.FirstAnswerDate - rq.QuestionCreationDate))/60.0 as MinutesToFirstAnswer,
         extract(epoch from (fa.FirstAnswerDate - rq.QuestionCreationDate))/3600.0 as HoursToFirstAnswer
  from recent_questions rq
  left join first_answer fa on fa.QuestionId = rq.QuestionId
  left join accepted_map am on am.QuestionId = rq.QuestionId
), speed_buckets as (
  select qj.*,
         case
           when MinutesToFirstAnswer is null then 'no-answer'
           when MinutesToFirstAnswer <= 15 then '00-15m'
           when MinutesToFirstAnswer <= 60 then '16-60m'
           when MinutesToFirstAnswer <= 240 then '01-04h'
           when MinutesToFirstAnswer <= 1440 then '04-24h'
           else '24h+'
         end as SpeedBucket
  from qa_join qj
), question_enriched as (
  select sb.*,
         coalesce(aqv.UpVotes,0) as QUpVotes,
         coalesce(aqv.DownVotes,0) as QDownVotes,
         coalesce(aqv.BountyStarts,0) as QBountyStarts,
         coalesce(aqv.BountyCloses,0) as QBountyCloses,
         coalesce(aqv.BountyAwarded,0) as QBountyAwarded,
         coalesce(ca.CommentCount,0) as QCommentCount,
         ca.LastCommentDate as QLastCommentDate
  from speed_buckets sb
  left join agg_question_votes aqv on aqv.PostId = sb.QuestionId
  left join comments_agg ca on ca.PostId = sb.QuestionId
), accepted_answer_enriched as (
  select aa.Id as AcceptedAnswerId,
         aa.ParentId as QuestionId,
         aa.OwnerUserId as AcceptedAnswererId,
         aa.Score as AcceptedAnswerScore,
         aa.CreationDate as AcceptedAnswerDate,
         coalesce(av.UpVotes,0) as AUpVotes,
         coalesce(av.DownVotes,0) as ADownVotes,
         coalesce(cv.CommentCount,0) as ACommentCount,
         cv.LastCommentDate as ALastCommentDate
  from Posts aa
  left join agg_question_votes av on av.PostId = aa.Id
  left join comments_agg cv on cv.PostId = aa.Id
  where aa.PostTypeId = 2
), asker_profile as (
  select us.UserId as AskerId,
         us.Reputation as AskerReputation,
         extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - us.UserCreationDate))/86400.0 as AskerAccountAgeDays,
         coalesce(ba.TotalBadges,0) as AskerTotalBadges,
         coalesce(ba.GoldBadges,0) as AskerGoldBadges,
         coalesce(ba.SilverBadges,0) as AskerSilverBadges,
         coalesce(ba.BronzeBadges,0) as AskerBronzeBadges
  from user_stats us
  left join badge_agg ba on ba.UserId = us.UserId
), answerer_profile as (
  select us.UserId as AnswererId,
         us.Reputation as AnswererReputation,
         extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - us.UserCreationDate))/86400.0 as AnswererAccountAgeDays,
         coalesce(ba.TotalBadges,0) as AnswererTotalBadges,
         coalesce(ba.GoldBadges,0) as AnswererGoldBadges,
         coalesce(ba.SilverBadges,0) as AnswererSilverBadges,
         coalesce(ba.BronzeBadges,0) as AnswererBronzeBadges
  from user_stats us
  left join badge_agg ba on ba.UserId = us.UserId
), question_tag_rank as (
  select qe.QuestionId,
         array_agg(tt.tag order by tt.tag) as TopTagsPresent,
         count(tt.tag) as TopTagMatches
  from question_enriched qe
  left join tag_expansion te on te.QuestionId = qe.QuestionId
  left join top_tags tt on tt.tag = te.tag
  group by qe.QuestionId
), activity_window as (
  select ph.PostId,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditDate,
         max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditDate,
         count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
         count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15)) as ModEventCount
  from PostHistory ph
  group by ph.PostId
), duplicates as (
  select pl.PostId as DuplicateOfId,
         pl.RelatedPostId as CanonicalId,
         count(*) as DuplicateLinks
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId, pl.RelatedPostId
), final as (
  select
    qe.QuestionId,
    qe.Title,
    qe.Tags,
    qe.QuestionCreationDate,
    qe.ViewCount,
    qe.QuestionScore,
    qe.QUpVotes,
    qe.QDownVotes,
    qe.QBountyStarts,
    qe.QBountyCloses,
    qe.QBountyAwarded,
    qe.QCommentCount,
    qe.QLastCommentDate,
    qe.FirstAnswerDate,
    qe.AcceptedAnswerId,
    qe.MinutesToFirstAnswer,
    qe.HoursToFirstAnswer,
    qe.SpeedBucket,
    qtr.TopTagsPresent,
    qtr.TopTagMatches,
    aw.FirstEditDate,
    aw.LastEditDate,
    aw.EditCount,
    aw.ModEventCount,
    dup.CanonicalId as DuplicateCanonicalId,
    dup.DuplicateLinks,
    ap.AcceptedAnswerScore,
    ap.AUpVotes as AcceptedUpVotes,
    ap.ADownVotes as AcceptedDownVotes,
    ap.ACommentCount as AcceptedCommentCount,
    ap.ALastCommentDate as AcceptedLastCommentDate,
    ask.AskerReputation,
    ask.AskerAccountAgeDays,
    ask.AskerTotalBadges,
    ask.AskerGoldBadges,
    ask.AskerSilverBadges,
    ask.AskerBronzeBadges,
    ans.AnswererReputation,
    ans.AnswererAccountAgeDays,
    ans.AnswererTotalBadges,
    ans.AnswererGoldBadges,
    ans.AnswererSilverBadges,
    ans.AnswererBronzeBadges
  from question_enriched qe
  left join question_tag_rank qtr on qtr.QuestionId = qe.QuestionId
  left join activity_window aw on aw.PostId = qe.QuestionId
  left join duplicates dup on dup.DuplicateOfId = qe.QuestionId
  left join accepted_answer_enriched ap on ap.AcceptedAnswerId = qe.AcceptedAnswerId
  left join asker_profile ask on ask.AskerId = qe.AskerId
  left join answerer_profile ans on ans.AnswererId = ap.AcceptedAnswererId
)
select *
from final
where
  (TopTagMatches >= 1 or QBountyAwarded > 0 or SpeedBucket in ('00-15m','16-60m'))
order by
  QBountyAwarded desc nulls last,
  TopTagMatches desc,
  MinutesToFirstAnswer nulls last,
  ViewCount desc
limit 500;