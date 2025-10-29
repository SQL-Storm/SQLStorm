-- {"query": "583.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3418}
with
q as (
  select p.Id as QuestionId,
         p.CreationDate as QuestionDate,
         p.OwnerUserId as AskerId,
         p.Score as QuestionScore,
         p.ViewCount,
         p.Tags,
         p.AcceptedAnswerId,
         p.Title,
         coalesce(nullif(trim(p.OwnerDisplayName), ''), u.DisplayName) as AskerDisplayName
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1
),
a as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswererId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerDate,
         row_number() over (partition by a.ParentId order by a.Score desc, a.Id) as rn_by_score
  from Posts a
  where a.PostTypeId = 2
),
qa as (
  select q.*,
         a.AnswerId,
         a.AnswererId,
         a.AnswerScore,
         a.AnswerDate,
         a.rn_by_score,
         case when q.AcceptedAnswerId = a.AnswerId then 1 else 0 end as IsAccepted
  from q
  left join a on a.QuestionId = q.QuestionId
),
comments_agg as (
  select c.PostId,
         count(*) as CommentCount,
         sum(coalesce(c.Score, 0)) as CommentScoreSum,
         max(c.CreationDate) as LastCommentDate,
         count(*) filter (where c.Score > 0) as UpvotedComments,
         count(*) filter (where c.Score < 0) as DownvotedComments
  from Comments c
  group by c.PostId
),
votes_agg as (
  select v.PostId,
         count(*) filter (where v.VoteTypeId = 2) as UpVotesOnPost,
         count(*) filter (where v.VoteTypeId = 3) as DownVotesOnPost,
         count(*) filter (where v.VoteTypeId = 5) as FavoriteVotesOnPost,
         count(*) filter (where v.VoteTypeId = 8) as BountyStarts,
         sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyAmountTotal
  from Votes v
  group by v.PostId
),
ph_close as (
  select ph.PostId,
         min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstClosedDate,
         min(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as FirstReopenDate,
         max(case when ph.PostHistoryTypeId = 10 then
                    -- try to convert ph.Comment to integer in a dialect-agnostic way:
                    -- trim non-digit characters and cast; if not numeric, result will be NULL.
                    (case
                       when ph.Comment ~ '^\s*-?\d+\s*$' then cast(trim(ph.Comment) as integer)
                       else null
                    end)
                  end) as AnyCloseReasonId
  from PostHistory ph
  group by ph.PostId
),
dupes as (
  select pl.PostId as DuplicateId,
         pl.RelatedPostId as TargetId,
         min(pl.CreationDate) as FirstDuplicateLinkDate
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId, pl.RelatedPostId
),
tag_expanded as (
  select q.QuestionId,
         unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as TagName
  from q
  where q.Tags is not null and length(q.Tags) >= 2
),
tag_stats as (
  select te.QuestionId,
         array_agg(te.TagName order by te.TagName) as TagsArray,
         count(*) as TagCount,
         string_agg(te.TagName, ',' order by te.TagName) as TagsCSV
  from tag_expanded te
  group by te.QuestionId
),
user_activity as (
  select u.Id as UserId,
         u.Reputation,
         u.UpVotes,
         u.DownVotes,
         u.Views as ProfileViews,
         coalesce(u.Location, 'Unknown') as Location,
         date_part('year', age(cast('2024-10-01 12:34:56' as timestamp), u.CreationDate)) as AccountAgeYears,
         count(b.Id) as BadgeCount,
         sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
         sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
         sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.Location, u.CreationDate
),
question_metrics as (
  select
    qa.QuestionId,
    qa.QuestionDate,
    qa.AskerId,
    qa.AskerDisplayName,
    qa.QuestionScore,
    qa.ViewCount,
    qa.Title,
    ts.TagsArray,
    ts.TagCount,
    ts.TagsCSV,
    max(qa.IsAccepted) as HasAcceptedAnswer,
    min(case when qa.IsAccepted = 1 then qa.AnswerDate end) as AcceptedAnswerDate,
    max(qa.AnswerScore) filter (where qa.rn_by_score = 1) as TopAnswerScore,
    min(qa.AnswerDate) as FirstAnswerDate,
    count(qa.AnswerId) as AnswerCount,
    sum(qa.AnswerScore) as SumAnswerScores,
    avg(cast(qa.AnswerScore as numeric)) as AvgAnswerScore,
    percentile_cont(0.5) within group (order by qa.AnswerScore) as MedianAnswerScore
  from qa
  left join tag_stats ts on ts.QuestionId = qa.QuestionId
  group by qa.QuestionId, qa.QuestionDate, qa.AskerId, qa.AskerDisplayName, qa.QuestionScore, qa.ViewCount, qa.Title, ts.TagsArray, ts.TagCount, ts.TagsCSV
),
answerer_quality as (
  select
    qa.QuestionId,
    qa.AnswererId,
    count(*) as AnswersOnQuestion,
    max(qa.AnswerScore) as BestScoreByAnswerer,
    sum(case when qa.IsAccepted = 1 then 1 else 0 end) as AcceptedByAnswerer
  from qa
  where qa.AnswerId is not null
  group by qa.QuestionId, qa.AnswererId
),
answerer_rank as (
  select
    aq.QuestionId,
    aq.AnswererId,
    aq.AnswersOnQuestion,
    aq.BestScoreByAnswerer,
    aq.AcceptedByAnswerer,
    row_number() over (partition by aq.QuestionId order by aq.AcceptedByAnswerer desc, aq.BestScoreByAnswerer desc, aq.AnswersOnQuestion desc, aq.AnswererId) as RankByAcceptanceThenScore
  from answerer_quality aq
),
question_enriched as (
  select
    qm.*,
    coalesce(ca.CommentCount, 0) as QuestionCommentCount,
    coalesce(ca.CommentScoreSum, 0) as QuestionCommentScoreSum,
    ca.LastCommentDate as QuestionLastCommentDate,
    coalesce(va.UpVotesOnPost, 0) as QuestionUpVotes,
    coalesce(va.DownVotesOnPost, 0) as QuestionDownVotes,
    coalesce(va.FavoriteVotesOnPost, 0) as QuestionFavorites,
    coalesce(va.BountyStarts, 0) as BountyStarts,
    coalesce(va.BountyAmountTotal, 0) as BountyAmountTotal,
    pc.FirstClosedDate,
    pc.FirstReopenDate,
    pc.AnyCloseReasonId
  from question_metrics qm
  left join comments_agg ca on ca.PostId = qm.QuestionId
  left join votes_agg va on va.PostId = qm.QuestionId
  left join ph_close pc on pc.PostId = qm.QuestionId
),
answer_enriched as (
  select
    qa.QuestionId,
    qa.AnswerId,
    qa.AnswererId,
    qa.IsAccepted,
    qa.AnswerScore,
    qa.AnswerDate,
    coalesce(ac.CommentCount, 0) as AnswerCommentCount,
    coalesce(ac.CommentScoreSum, 0) as AnswerCommentScoreSum,
    va.UpVotesOnPost as AnswerUpVotes,
    va.DownVotesOnPost as AnswerDownVotes
  from qa
  left join comments_agg ac on ac.PostId = qa.AnswerId
  left join votes_agg va on va.PostId = qa.AnswerId
  where qa.AnswerId is not null
),
question_dupe as (
  select
    qe.*,
    d.TargetId as DuplicateOfId,
    d.FirstDuplicateLinkDate
  from question_enriched qe
  left join dupes d on d.DuplicateId = qe.QuestionId
),
asker_profile as (
  select
    qe.QuestionId,
    ua.Reputation as AskerReputation,
    ua.UpVotes as AskerUpVotes,
    ua.DownVotes as AskerDownVotes,
    ua.ProfileViews as AskerProfileViews,
    ua.Location as AskerLocation,
    ua.AccountAgeYears as AskerAccountAgeYears,
    ua.BadgeCount as AskerBadgeCount,
    ua.GoldBadges as AskerGoldBadges,
    ua.SilverBadges as AskerSilverBadges,
    ua.BronzeBadges as AskerBronzeBadges
  from question_enriched qe
  left join user_activity ua on ua.UserId = qe.AskerId
),
time_spans as (
  select
    qd.QuestionId,
    extract(epoch from (coalesce(qd.AcceptedAnswerDate, qd.FirstAnswerDate) - qd.QuestionDate)) as SecsToFirstResolution,
    extract(epoch from (qd.FirstAnswerDate - qd.QuestionDate)) as SecsToFirstAnswer,
    extract(epoch from (qd.FirstClosedDate - qd.QuestionDate)) as SecsToClose
  from question_dupe qd
),
final_scored as (
  select
    qd.*,
    ap.AskerReputation,
    ap.AskerUpVotes,
    ap.AskerDownVotes,
    ap.AskerProfileViews,
    ap.AskerLocation,
    ap.AskerAccountAgeYears,
    ap.AskerBadgeCount,
    ap.AskerGoldBadges,
    ap.AskerSilverBadges,
    ap.AskerBronzeBadges,
    ts.SecsToFirstResolution,
    ts.SecsToFirstAnswer,
    ts.SecsToClose,
    coalesce(qd.QuestionUpVotes - qd.QuestionDownVotes, 0) as NetVotes,
    case
      when qd.TagCount is null or qd.TagCount = 0 then 0
      else qd.TagCount
    end as TagCountNormalized,
    case
      when qd.ViewCount is null or qd.ViewCount = 0 then 0
      else ln(qd.ViewCount + 1)
    end as LogViews,
    case
      when qd.QuestionFavorites > 0 then 1 else 0
    end as HasFavorites,
    case
      when qd.BountyAmountTotal > 0 then 1 else 0
    end as HasBounty,
    case
      when qd.AnyCloseReasonId in (101,1) then 1 else 0
    end as IsDuplicateMarked,
    case
      when qd.FirstClosedDate is not null and qd.FirstReopenDate is not null and qd.FirstReopenDate > qd.FirstClosedDate then 1 else 0
    end as WasReopened
  from question_dupe qd
  left join asker_profile ap on ap.QuestionId = qd.QuestionId
  left join time_spans ts on ts.QuestionId = qd.QuestionId
),
ranked as (
  select
    fs.*,
    dense_rank() over (order by coalesce(fs.TopAnswerScore, -2147483648) desc, coalesce(fs.NetVotes, -2147483648) desc, coalesce(fs.ViewCount, -2147483648) desc) as OverallRank,
    ntile(10) over (order by coalesce(fs.ViewCount, 0) desc) as ViewDecile,
    row_number() over (partition by coalesce(fs.TagCount,0) order by coalesce(fs.QuestionCommentCount,0) desc) as RowNumWithinTagCount
  from final_scored fs
),
top_answerers as (
  select
    ar.QuestionId,
    ar.AnswererId,
    ar.RankByAcceptanceThenScore,
    ua.Reputation as AnswererReputation,
    ua.BadgeCount as AnswererBadgeCount
  from answerer_rank ar
  left join user_activity ua on ua.UserId = ar.AnswererId
  where ar.RankByAcceptanceThenScore <= 3
)
select
  r.QuestionId,
  r.Title,
  r.TagsCSV,
  r.TagCount,
  r.AskerDisplayName,
  r.AskerReputation,
  r.AskerBadgeCount,
  r.QuestionDate,
  r.ViewCount,
  r.QuestionScore,
  r.NetVotes,
  r.QuestionUpVotes,
  r.QuestionDownVotes,
  r.QuestionFavorites,
  r.BountyAmountTotal,
  r.HasBounty,
  r.HasFavorites,
  r.AnswerCount,
  r.TopAnswerScore,
  r.SumAnswerScores,
  r.AvgAnswerScore,
  r.MedianAnswerScore,
  r.QuestionCommentCount,
  r.QuestionCommentScoreSum,
  r.QuestionLastCommentDate,
  r.FirstClosedDate,
  r.FirstReopenDate,
  r.IsDuplicateMarked,
  r.DuplicateOfId,
  r.WasReopened,
  r.SecsToFirstAnswer,
  r.SecsToFirstResolution,
  r.SecsToClose,
  r.LogViews,
  r.OverallRank,
  r.ViewDecile,
  r.RowNumWithinTagCount,
  string_agg(
    concat('U', ta.AnswererId, ':R', ta.RankByAcceptanceThenScore, ':Rep', coalesce(ta.AnswererReputation,0), ':B', coalesce(ta.AnswererBadgeCount,0)),
    ' | ' order by ta.RankByAcceptanceThenScore, ta.AnswererId
  ) as TopAnswerersSummary
from ranked r
left join top_answerers ta on ta.QuestionId = r.QuestionId
where coalesce(r.TagCount, 0) >= 1
  and (r.SecsToFirstAnswer is null or r.SecsToFirstAnswer >= 0)
  and (r.FirstClosedDate is null or r.FirstClosedDate >= r.QuestionDate)
  and (
    r.ViewCount is null or
    r.ViewCount = 0 or
    r.ViewCount >= (
      select percentile_disc(0.75) within group (order by coalesce(ViewCount,0))
      from Posts
      where PostTypeId = 1
    )
  )
group by
  r.QuestionId, r.Title, r.TagsCSV, r.TagCount, r.AskerDisplayName, r.AskerReputation, r.AskerBadgeCount,
  r.QuestionDate, r.ViewCount, r.QuestionScore, r.NetVotes, r.QuestionUpVotes, r.QuestionDownVotes, r.QuestionFavorites,
  r.BountyAmountTotal, r.HasBounty, r.HasFavorites, r.AnswerCount, r.TopAnswerScore, r.SumAnswerScores, r.AvgAnswerScore,
  r.MedianAnswerScore, r.QuestionCommentCount, r.QuestionCommentScoreSum, r.QuestionLastCommentDate, r.FirstClosedDate,
  r.FirstReopenDate, r.IsDuplicateMarked, r.DuplicateOfId, r.WasReopened, r.SecsToFirstAnswer, r.SecsToFirstResolution,
  r.SecsToClose, r.LogViews, r.OverallRank, r.ViewDecile, r.RowNumWithinTagCount
order by r.OverallRank, r.QuestionId
limit 200;