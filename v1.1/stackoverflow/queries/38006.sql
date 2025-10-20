-- {"query": "38006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2536} 
with recent_q as (
  select p.Id as QuestionId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         p.Tags,
         coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answers as (
  select a.ParentId as QuestionId,
         a.Id as AnswerId,
         a.OwnerUserId as AnswerOwnerId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreationDate
  from Posts a
  where a.PostTypeId = 2
),
q_votes as (
  select v.PostId as QuestionId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
  from Votes v
  group by v.PostId
),
a_votes as (
  select a.ParentId as QuestionId,
         count(*) filter (where v.VoteTypeId = 2) as AnswerUpVotes,
         count(*) filter (where v.VoteTypeId = 3) as AnswerDownVotes
  from Posts a
  join Votes v on v.PostId = a.Id
  where a.PostTypeId = 2
  group by a.ParentId
),
first_answer as (
  select a.QuestionId,
         min(a.AnswerCreationDate) as FirstAnswerTime
  from answers a
  group by a.QuestionId
),
accepted as (
  select q.Id as QuestionId,
         q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
comment_stats as (
  select c.PostId as QuestionId,
         count(*) as CommentCount,
         avg(c.Score) as AvgCommentScore
  from Comments c
  group by c.PostId
),
tag_expansion as (
  select rq.QuestionId,
         unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) as tag
  from recent_q rq
  where rq.Tags is not null
),
tag_rank as (
  select te.tag,
         count(*) as TagUseCount,
         percentile_disc(0.5) within group (order by rq.Score) as MedianQScore
  from tag_expansion te
  join recent_q rq on rq.QuestionId = te.QuestionId
  group by te.tag
  having count(*) >= 5
),
user_basics as (
  select u.Id as UserId,
         u.Reputation,
         u.UpVotes,
         u.DownVotes,
         u.CreationDate as UserCreationDate
  from Users u
),
badge_agg as (
  select b.UserId,
         count(*) as TotalBadges,
         count(*) filter (where b.Class = 1) as GoldBadges,
         count(*) filter (where b.Class = 2) as SilverBadges,
         count(*) filter (where b.Class = 3) as BronzeBadges
  from Badges b
  group by b.UserId
),
q_owner as (
  select rq.QuestionId,
         ub.Reputation as OwnerReputation,
         ub.UpVotes as OwnerUpVotes,
         ub.DownVotes as OwnerDownVotes,
         coalesce(ba.TotalBadges,0) as OwnerBadges,
         coalesce(ba.GoldBadges,0) as OwnerGold,
         coalesce(ba.SilverBadges,0) as OwnerSilver,
         coalesce(ba.BronzeBadges,0) as OwnerBronze
  from recent_q rq
  left join user_basics ub on ub.UserId = rq.OwnerUserId
  left join badge_agg ba on ba.UserId = rq.OwnerUserId
),
answerer_diversity as (
  select a.QuestionId,
         count(distinct a.AnswerOwnerId) as DistinctAnswerers,
         avg(a.AnswerScore) as AvgAnswerScore
  from answers a
  group by a.QuestionId
),
dup_links as (
  select pl.PostId as QuestionId,
         count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
         count(*) filter (where pl.LinkTypeId = 1) as LinkedRefs
  from PostLinks pl
  group by pl.PostId
),
close_events as (
  select ph.PostId as QuestionId,
         count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstCloseDate,
         count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotes
  from PostHistory ph
  group by ph.PostId
),
hot_events as (
  select ph.PostId as QuestionId,
         max(case when ph.PostHistoryTypeId = 52 then 1 else 0 end) as WasHot,
         max(case when ph.PostHistoryTypeId = 53 then 1 else 0 end) as WasUnHot
  from PostHistory ph
  group by ph.PostId
),
bounty as (
  select v.PostId as QuestionId,
         sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
         sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded
  from Votes v
  group by v.PostId
),
time_bins as (
  select rq.QuestionId,
         date_trunc('month', rq.CreationDate) as MonthBin
  from recent_q rq
),
month_agg as (
  select tb.MonthBin,
         count(*) as QuestionsInMonth,
         avg(rq.Score) as AvgQScoreInMonth,
         avg(rq.ViewCount) as AvgViewsInMonth
  from time_bins tb
  join recent_q rq on rq.QuestionId = tb.QuestionId
  group by tb.MonthBin
),
rank_within_tag as (
  select te.tag,
         rq.QuestionId,
         rq.Score,
         dense_rank() over (partition by te.tag order by rq.Score desc, rq.ViewCount desc, rq.CreationDate asc) as ScoreRankInTag
  from tag_expansion te
  join recent_q rq on rq.QuestionId = te.QuestionId
),
best_tag_per_q as (
  select rwt.QuestionId,
         rwt.tag as TopTagByScore,
         rwt.ScoreRankInTag
  from (
    select rwt.*,
           row_number() over (partition by rwt.QuestionId order by rwt.ScoreRankInTag asc, rwt.tag asc) as rn
    from rank_within_tag rwt
  ) rwt
  where rwt.rn = 1
),
accepted_join as (
  select ac.QuestionId,
         a.AnswerOwnerId as AcceptedOwnerId,
         a.AnswerScore as AcceptedAnswerScore,
         a.AnswerCreationDate as AcceptedAnswerDate
  from accepted ac
  join answers a on a.AnswerId = ac.AcceptedAnswerId
),
accepted_owner_stats as (
  select aj.QuestionId,
         ub.Reputation as AcceptedOwnerReputation,
         coalesce(ba.TotalBadges,0) as AcceptedOwnerBadges
  from accepted_join aj
  left join user_basics ub on ub.UserId = aj.AcceptedOwnerId
  left join badge_agg ba on ba.UserId = aj.AcceptedOwnerId
),
quality_signals as (
  select rq.QuestionId,
         case when rq.Score >= 5 then 1 else 0 end as IsWellScored,
         case when rq.ViewCount >= 1000 then 1 else 0 end as IsWellViewed,
         case when coalesce(qv.UpVotes,0) - coalesce(qv.DownVotes,0) >= 5 then 1 else 0 end as IsNetUpvoted,
         case when ae.AnswerUpVotes >= ae.AnswerDownVotes then 1 else 0 end as AnswersNetPositive
  from recent_q rq
  left join q_votes qv on qv.QuestionId = rq.QuestionId
  left join a_votes ae on ae.QuestionId = rq.QuestionId
),
fast_answer as (
  select rq.QuestionId,
         extract(epoch from (fa.FirstAnswerTime - rq.CreationDate)) / 3600.0 as HoursToFirstAnswer
  from recent_q rq
  left join first_answer fa on fa.QuestionId = rq.QuestionId
),
final as (
  select
    rq.QuestionId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    qv.UpVotes as QUp,
    qv.DownVotes as QDown,
    qv.Favorites as QFavs,
    ae.AnswerUpVotes as AUp,
    ae.AnswerDownVotes as ADown,
    cs.CommentCount,
    cs.AvgCommentScore,
    coalesce(dl.DuplicateLinks,0) as DuplicateLinks,
    coalesce(dl.LinkedRefs,0) as LinkedRefs,
    coalesce(ce.CloseVotes,0) as CloseVotes,
    ce.FirstCloseDate,
    coalesce(ce.ReopenVotes,0) as ReopenVotes,
    he.WasHot,
    he.WasUnHot,
    bty.BountyStarted,
    bty.BountyAwarded,
    qb.IsWellScored,
    qb.IsWellViewed,
    qb.IsNetUpvoted,
    qb.AnswersNetPositive,
    fa.HoursToFirstAnswer,
    qt.TopTagByScore,
    tr.TagUseCount as TopTagUseCount,
    tr.MedianQScore as TopTagMedianQScore,
    qo.OwnerReputation,
    qo.OwnerUpVotes,
    qo.OwnerDownVotes,
    qo.OwnerBadges,
    qo.OwnerGold,
    qo.OwnerSilver,
    qo.OwnerBronze,
    aos.AcceptedOwnerReputation,
    aos.AcceptedOwnerBadges,
    ma.MonthBin,
    ma.QuestionsInMonth,
    ma.AvgQScoreInMonth,
    ma.AvgViewsInMonth
  from recent_q rq
  left join q_votes qv on qv.QuestionId = rq.QuestionId
  left join a_votes ae on ae.QuestionId = rq.QuestionId
  left join comment_stats cs on cs.QuestionId = rq.QuestionId
  left join dup_links dl on dl.QuestionId = rq.QuestionId
  left join close_events ce on ce.QuestionId = rq.QuestionId
  left join hot_events he on he.QuestionId = rq.QuestionId
  left join bounty bty on bty.QuestionId = rq.QuestionId
  left join fast_answer fa on fa.QuestionId = rq.QuestionId
  left join best_tag_per_q qt on qt.QuestionId = rq.QuestionId
  left join tag_rank tr on tr.tag = qt.TopTagByScore
  left join q_owner qo on qo.QuestionId = rq.QuestionId
  left join accepted_owner_stats aos on aos.QuestionId = rq.QuestionId
  left join time_bins tb on tb.QuestionId = rq.QuestionId
  left join month_agg ma on ma.MonthBin = tb.MonthBin
  left join quality_signals qb on qb.QuestionId = rq.QuestionId
)
select *
from final
where coalesce(WasHot,0) = 1
   or (IsWellScored = 1 and coalesce(DuplicateLinks,0) = 0)
order by Score desc nulls last, ViewCount desc nulls last, CreationDate asc
limit 500;