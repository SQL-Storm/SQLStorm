-- {"query": "184.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3155} 
with
q as (
  select p.Id as QuestionId,
         p.CreationDate,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.Title,
         p.Tags,
         p.AcceptedAnswerId,
         date_trunc('month', p.CreationDate) as MonthBucket
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswerUserId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreationDate
  from Posts a
  where a.PostTypeId = 2
),
first_answer as (
  select a.QuestionId,
         min(a.AnswerCreationDate) as FirstAnswerDate
  from a
  group by a.QuestionId
),
votes_agg as (
  select v.PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
         sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
         count(*) as TotalVotes
  from Votes v
  group by v.PostId
),
comments_agg as (
  select c.PostId,
         count(*) as CommentCount,
         max(c.CreationDate) as LastCommentDate,
         sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments
  from Comments c
  group by c.PostId
),
links as (
  select pl.PostId,
         sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
         sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinks
  from PostLinks pl
  group by pl.PostId
),
closures as (
  select ph.PostId,
         min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstCloseDate,
         max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenDate,
         bool_or(ph.PostHistoryTypeId = 10) as EverClosed,
         string_agg(distinct case when ph.PostHistoryTypeId = 10 then coalesce(ph.Comment,'') end, ',' order by ph.CreationDate) as CloseReasonsRaw
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11)
  group by ph.PostId
),
accepted as (
  select q.QuestionId,
         q.AcceptedAnswerId,
         a2.OwnerUserId as AcceptedOwnerUserId,
         a2.Score as AcceptedAnswerScore,
         a2.CreationDate as AcceptedAnswerDate
  from q
  left join Posts a2 on a2.Id = q.AcceptedAnswerId
),
parsed_tags as (
  select q.QuestionId,
         unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as TagName
  from q
  where q.Tags is not null and q.Tags like '<%>'
),
tag_rank as (
  select pt.QuestionId,
         pt.TagName,
         row_number() over (partition by pt.QuestionId order by length(pt.TagName) desc, pt.TagName) as TagLenRank,
         count(*) over (partition by pt.QuestionId) as TagCount
  from parsed_tags pt
),
user_stats as (
  select u.Id as UserId,
         u.Reputation,
         u.CreationDate,
         u.UpVotes as UserUpVotes,
         u.DownVotes as UserDownVotes,
         u.Views as ProfileViews,
         coalesce(nullif(trim(u.Location),''),'Unknown') as CleanLocation
  from Users u
),
badge_counts as (
  select b.UserId,
         sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
         sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
         sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
         count(*) as TotalBadges,
         sum(case when b.TagBased = 1 then 1 else 0 end) as TagBadges
  from Badges b
  group by b.UserId
),
question_activity as (
  select
    q.QuestionId,
    q.MonthBucket,
    coalesce(v.UpVotes,0) as QUpVotes,
    coalesce(v.DownVotes,0) as QDownVotes,
    coalesce(v.TotalVotes,0) as QTotalVotes,
    coalesce(c.CommentCount,0) as QCommentCount,
    coalesce(l.LinkedCount,0) as LinkedCount,
    coalesce(l.DuplicateLinks,0) as DuplicateLinks,
    coalesce(cl.FirstCloseDate, null) as FirstCloseDate,
    coalesce(cl.LastReopenDate, null) as LastReopenDate,
    coalesce(cl.EverClosed, false) as EverClosed,
    cl.CloseReasonsRaw
  from q
  left join votes_agg v on v.PostId = q.QuestionId
  left join comments_agg c on c.PostId = q.QuestionId
  left join links l on l.PostId = q.QuestionId
  left join closures cl on cl.PostId = q.QuestionId
),
answer_activity as (
  select
    a.QuestionId,
    count(*) as Answers,
    sum(case when a.AnswerScore > 0 then 1 else 0 end) as PosAnswers,
    avg(a.AnswerScore::numeric) as AvgAnswerScore,
    max(a.AnswerScore) as MaxAnswerScore
  from a
  group by a.QuestionId
),
question_quality as (
  select
    qa.QuestionId,
    case
      when qa.QUpVotes + qa.QDownVotes = 0 then null
      else (qa.QUpVotes::numeric - qa.QDownVotes::numeric) / nullif(qa.QUpVotes + qa.QDownVotes, 0)
    end as NetVoteRatio,
    (qa.QCommentCount::numeric / nullif(nullif(q.ViewCount,0),0)) as CommentsPerView,
    case
      when qa.EverClosed and qa.LastReopenDate is null then 'Closed'
      when qa.EverClosed and qa.LastReopenDate is not null then 'Reopened'
      else 'Open'
    end as CloseState,
    (qa.LinkedCount - qa.DuplicateLinks) as NetLinks
  from question_activity qa
  join q on q.QuestionId = qa.QuestionId
),
final_rank as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    qa.QUpVotes,
    qa.QDownVotes,
    qa.QTotalVotes,
    qa.QCommentCount,
    qa.LinkedCount,
    qa.DuplicateLinks,
    qq.NetVoteRatio,
    qq.CommentsPerView,
    qq.CloseState,
    qq.NetLinks,
    aa.Answers,
    aa.PosAnswers,
    aa.AvgAnswerScore,
    aa.MaxAnswerScore,
    fa.FirstAnswerDate,
    extract(epoch from (fa.FirstAnswerDate - q.CreationDate)) as SecsToFirstAnswer,
    ac.AcceptedAnswerId,
    ac.AcceptedAnswerScore,
    ac.AcceptedAnswerDate,
    extract(epoch from (ac.AcceptedAnswerDate - q.CreationDate)) as SecsToAccept,
    u.Reputation as AskerRep,
    coalesce(b.TotalBadges,0) as AskerBadges,
    coalesce(b.GoldBadges,0) as AskerGold,
    coalesce(b.SilverBadges,0) as AskerSilver,
    coalesce(b.BronzeBadges,0) as AskerBronze,
    u.CleanLocation as AskerLocation,
    tr.TagName as LongestTag,
    tr.TagCount as TagCount,
    row_number() over (
      partition by q.MonthBucket
      order by
        coalesce(aa.Answers,0) desc,
        coalesce(qa.QUpVotes,0) - coalesce(qa.QDownVotes,0) desc,
        coalesce(ac.AcceptedAnswerScore, -9999) desc,
        q.ViewCount desc,
        q.Score desc,
        q.CreationDate asc
    ) as MonthRank,
    dense_rank() over (
      order by
        (coalesce(aa.AvgAnswerScore,0) * 2
         + coalesce(qa.QUpVotes,0)
         - coalesce(qa.QDownVotes,0)
         + least(coalesce(q.ViewCount,0) / 1000.0, 100)
         + case when qq.CloseState = 'Open' then 10 when qq.CloseState = 'Reopened' then 3 else -20 end
         + least(coalesce(aa.Answers,0), 10)
         + coalesce(qq.NetLinks,0)
        ) desc
    ) as GlobalDenseRank
  from q
  left join question_activity qa on qa.QuestionId = q.QuestionId
  left join answer_activity aa on aa.QuestionId = q.QuestionId
  left join first_answer fa on fa.QuestionId = q.QuestionId
  left join accepted ac on ac.QuestionId = q.QuestionId
  left join user_stats u on u.UserId = q.OwnerUserId
  left join badge_counts b on b.UserId = q.OwnerUserId
  left join tag_rank tr on tr.QuestionId = q.QuestionId and tr.TagLenRank = 1
),
dup_resolution as (
  select
    f.*,
    case
      when f.AcceptedAnswerId is null and f.Answers = 0 and f.QTotalVotes = 0 then 'Orphan'
      when f.AcceptedAnswerId is null and f.EverClosed is true then 'Closed without accept'
      when f.AcceptedAnswerId is null and f.Answers > 0 then 'Unaccepted'
      when f.AcceptedAnswerId is not null then 'Accepted'
      else 'Other'
    end as ResolutionBucket
  from final_rank f
  left join question_activity qa on qa.QuestionId = f.QuestionId
),
top_per_tag as (
  select
    f.QuestionId,
    f.Title,
    f.GlobalDenseRank,
    tr2.TagName,
    row_number() over (partition by tr2.TagName order by f.GlobalDenseRank asc, f.ViewCount desc) as RankWithinTag
  from final_rank f
  join parsed_tags tr2 on tr2.QuestionId = f.QuestionId
)
select
  f.QuestionId,
  f.Title,
  f.OwnerUserId,
  f.AskerRep,
  f.AskerBadges,
  f.AskerGold,
  f.AskerSilver,
  f.AskerBronze,
  f.AskerLocation,
  f.CreationDate,
  f.Score,
  f.ViewCount,
  f.AnswerCount,
  f.QUpVotes,
  f.QDownVotes,
  f.QTotalVotes,
  f.QCommentCount,
  f.LinkedCount,
  f.DuplicateLinks,
  f.NetVoteRatio,
  f.CommentsPerView,
  f.CloseState,
  f.NetLinks,
  f.Answers,
  f.PosAnswers,
  f.AvgAnswerScore,
  f.MaxAnswerScore,
  f.FirstAnswerDate,
  f.SecsToFirstAnswer,
  f.AcceptedAnswerId,
  f.AcceptedAnswerScore,
  f.AcceptedAnswerDate,
  f.SecsToAccept,
  f.LongestTag,
  f.TagCount,
  f.MonthRank,
  f.GlobalDenseRank,
  dr.ResolutionBucket,
  coalesce(string_agg(distinct case when tt.RankWithinTag <= 3 then tt.TagName end, ',' order by tt.TagName), '') as Top3TagMembership,
  case when f.CommentsPerView is null or f.CommentsPerView < 0 then 0 else 1 end as CommentsPerViewValid,
  case
    when f.NetVoteRatio is null then 'NoVotes'
    when f.NetVoteRatio > 0.5 then 'HighlyPositive'
    when f.NetVoteRatio between 0 and 0.5 then 'MixedPositive'
    when f.NetVoteRatio between -0.5 and 0 then 'MixedNegative'
    else 'HighlyNegative'
  end as SentimentBucket
from final_rank f
left join dup_resolution dr on dr.QuestionId = f.QuestionId
left join top_per_tag tt on tt.QuestionId = f.QuestionId
where
  (f.CreationDate >= (select min(CreationDate) from Posts where PostTypeId = 1)
   and f.CreationDate < (select max(CreationDate) from Posts where PostTypeId = 1))
  and (
    f.ViewCount > 0
    or exists (select 1 from Comments c where c.PostId = f.QuestionId and c.Score > 0)
    or exists (select 1 from Votes v where v.PostId = f.QuestionId and v.VoteTypeId in (2,3))
  )
group by
  f.QuestionId, f.Title, f.OwnerUserId, f.AskerRep, f.AskerBadges, f.AskerGold, f.AskerSilver, f.AskerBronze, f.AskerLocation,
  f.CreationDate, f.Score, f.ViewCount, f.AnswerCount, f.QUpVotes, f.QDownVotes, f.QTotalVotes, f.QCommentCount, f.LinkedCount, f.DuplicateLinks,
  f.NetVoteRatio, f.CommentsPerView, f.CloseState, f.NetLinks, f.Answers, f.PosAnswers, f.AvgAnswerScore, f.MaxAnswerScore,
  f.FirstAnswerDate, f.SecsToFirstAnswer, f.AcceptedAnswerId, f.AcceptedAnswerScore, f.AcceptedAnswerDate, f.SecsToAccept,
  f.LongestTag, f.TagCount, f.MonthRank, f.GlobalDenseRank, dr.ResolutionBucket
having
  coalesce(f.AvgAnswerScore, 0) >= (
    select percentile_disc(0.5) within group (order by coalesce(AvgAnswerScore,0))
    from final_rank
  )
order by
  f.GlobalDenseRank asc,
  f.MonthRank asc,
  f.ViewCount desc
limit 500;