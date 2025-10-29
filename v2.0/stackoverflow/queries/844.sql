with recent_questions as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    coalesce(nullif(trim(p.Title), ''), '[untitled]') as TitleNorm
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswererId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreationDate
  from Posts a
  where a.PostTypeId = 2
),
first_answer as (
  select
    a.QuestionId,
    a.AnswerId,
    a.AnswererId,
    a.AnswerScore,
    a.AnswerCreationDate,
    row_number() over (partition by a.QuestionId order by a.AnswerCreationDate asc, a.AnswerId asc) as rn,
    min(a.AnswerCreationDate) over (partition by a.QuestionId) as FirstAnswerAt
  from answers a
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesCnt,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesCnt,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteCnt,
    count(*) filter (where v.VoteTypeId in (2,3,5)) as TotalUDFF
  from Votes v
  group by v.PostId
),
comment_stats as (
  select
    c.PostId,
    count(*) as CommentCount,
    coalesce(sum(case when c.Score > 0 then 1 else 0 end), 0) as PosComments,
    max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
user_quality as (
  select
    u.Id as UserId,
    u.Reputation,
    coalesce(u.UpVotes,0) as UpVotes,
    coalesce(u.DownVotes,0) as DownVotes,
    coalesce(u.Views,0) as Views,
    date_part('day', cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate) as AccountAgeDays,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate
),
tag_unpivot as (
  select
    rq.QuestionId,
    unnest(string_to_array(substring(rq.Tags, 2, greatest(length(rq.Tags)-2,0)), '><')) as TagName
  from recent_questions rq
  where rq.Tags is not null
),
tag_stats as (
  select
    tu.QuestionId,
    count(*) as TagCount,
    min(t.Count) as MinTagGlobalCount,
    max(t.Count) as MaxTagGlobalCount,
    avg(cast(t.Count as numeric)) as AvgTagGlobalCount
  from tag_unpivot tu
  left join Tags t on lower(t.TagName) = lower(tu.TagName)
  group by tu.QuestionId
),
dup_links as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where pl.LinkTypeId = 3) as DupCount,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
    min(pl.CreationDate) as FirstLinkAt
  from PostLinks pl
  group by pl.PostId
),
closure as (
  select
    ph.PostId as QuestionId,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosedAt,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenedAt,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
    count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
    max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonIdRaw
  from PostHistory ph
  group by ph.PostId
),
question_activity as (
  select
    rq.QuestionId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.TitleNorm,
    fa.FirstAnswerAt,
    min(fa.AnswerCreationDate) as FirstAnswerTime,
    count(a.AnswerId) as AnswerCount,
    sum(case when a.AnswerScore > 0 then 1 else 0 end) as PosAnswerCount,
    sum(case when a.AnswerScore < 0 then 1 else 0 end) as NegAnswerCount
  from recent_questions rq
  left join answers a on a.QuestionId = rq.QuestionId
  left join first_answer fa on fa.QuestionId = rq.QuestionId and fa.rn = 1
  group by rq.QuestionId, rq.CreationDate, rq.Score, rq.ViewCount, rq.OwnerUserId, rq.TitleNorm, fa.FirstAnswerAt
),
owner_vs_answerer as (
  select
    qa.QuestionId,
    qa.OwnerUserId as AskerId,
    fa.AnswererId as FirstAnswererId,
    case when fa.AnswererId is not null and qa.OwnerUserId = fa.AnswererId then 1 else 0 end as SelfAnswered
  from question_activity qa
  left join first_answer fa on fa.QuestionId = qa.QuestionId and fa.rn = 1
),
owner_stats as (
  select
    qa.QuestionId,
    uq.Reputation as AskerReputation,
    uq.GoldBadges as AskerGold,
    uq.SilverBadges as AskerSilver,
    uq.BronzeBadges as AskerBronze,
    uq.AccountAgeDays as AskerAgeDays
  from question_activity qa
  left join user_quality uq on uq.UserId = qa.OwnerUserId
),
engagement as (
  select
    qa.QuestionId,
    coalesce(v.UpVotesCnt,0) as UpVotesCnt,
    coalesce(v.DownVotesCnt,0) as DownVotesCnt,
    coalesce(v.FavoriteCnt,0) as FavoriteCnt,
    coalesce(cs.CommentCount,0) as CommentCount,
    coalesce(cs.PosComments,0) as PosComments,
    cs.LastCommentAt
  from question_activity qa
  left join votes_agg v on v.PostId = qa.QuestionId
  left join comment_stats cs on cs.PostId = qa.QuestionId
),
timings as (
  select
    qa.QuestionId,
    qa.CreationDate,
    qa.FirstAnswerTime,
    qa.AnswerCount,
    extract(epoch from (qa.FirstAnswerTime - qa.CreationDate)) as SecToFirstAnswer,
    extract(epoch from (coalesce(e.LastCommentAt, qa.CreationDate) - qa.CreationDate)) as SecToLastComment
  from question_activity qa
  left join engagement e on e.QuestionId = qa.QuestionId
),
quality_score as (
  select
    qa.QuestionId,
    qa.Score,
    qa.ViewCount,
    e.UpVotesCnt,
    e.DownVotesCnt,
    e.FavoriteCnt,
    e.CommentCount,
    ts.TagCount,
    greatest(1, ts.TagCount) as TagCountSafe,
    CAST(
      (coalesce(qa.Score,0) * 2
       + coalesce(e.UpVotesCnt,0) * 1.5
       - coalesce(e.DownVotesCnt,0) * 2
       + coalesce(e.FavoriteCnt,0) * 3
       + least(coalesce(qa.ViewCount,0) / 100.0, 50)
       + coalesce(e.CommentCount,0) * 0.25
       + least(coalesce(ts.AvgTagGlobalCount,0) / 1000.0, 30)
      ) AS numeric(18,4)
    ) as QualityScore
  from question_activity qa
  left join engagement e on e.QuestionId = qa.QuestionId
  left join tag_stats ts on ts.QuestionId = qa.QuestionId
),
ranked as (
  select
    qa.QuestionId,
    qa.CreationDate,
    qa.Score,
    qa.ViewCount,
    qa.AnswerCount,
    qa.PosAnswerCount,
    qa.NegAnswerCount,
    e.UpVotesCnt,
    e.DownVotesCnt,
    e.FavoriteCnt,
    e.CommentCount,
    e.PosComments,
    t.SecToFirstAnswer,
    t.SecToLastComment,
    os.AskerReputation,
    os.AskerGold, os.AskerSilver, os.AskerBronze, os.AskerAgeDays,
    tv.TagCount,
    coalesce(dl.DupCount,0) as DupCount,
    coalesce(dl.LinkedCount,0) as LinkedCount,
    cl.FirstClosedAt,
    cl.LastReopenedAt,
    cl.CloseEvents,
    cl.ReopenEvents,
    oaa.SelfAnswered,
    qs.QualityScore,
    dense_rank() over (order by qs.QualityScore desc nulls last, qa.ViewCount desc nulls last, qa.Score desc nulls last) as QualityRank,
    percent_rank() over (order by qs.QualityScore asc nulls last) as QualityPercentileLow,
    percent_rank() over (order by qs.QualityScore desc nulls last) as QualityPercentileHigh
  from question_activity qa
  left join engagement e on e.QuestionId = qa.QuestionId
  left join timings t on t.QuestionId = qa.QuestionId
  left join owner_stats os on os.QuestionId = qa.QuestionId
  left join tag_stats tv on tv.QuestionId = qa.QuestionId
  left join dup_links dl on dl.QuestionId = qa.QuestionId
  left join closure cl on cl.QuestionId = qa.QuestionId
  left join owner_vs_answerer oaa on oaa.QuestionId = qa.QuestionId
  left join quality_score qs on qs.QuestionId = qa.QuestionId
),
null_exercises as (
  select
    r.*,
    case
      when cl.FirstClosedAt is not null then 1
      when (coalesce(dl.DupCount,0) > 0 or coalesce(dl.LinkedCount,0) > 0) then 0
      else null
    end as NullableFlag,
    cast(coalesce(nullif(trim(cast(os.AskerReputation as text)), ''), '0') as int) as AskerReputationCoerced,
    case when t.SecToFirstAnswer is null then -1 else t.SecToFirstAnswer end as SecToFirstAnswerNullAsNeg1
  from ranked r
  left join closure cl on cl.QuestionId = r.QuestionId
  left join dup_links dl on dl.QuestionId = r.QuestionId
  left join timings t on t.QuestionId = r.QuestionId
  left join owner_stats os on os.QuestionId = r.QuestionId
),
rolling as (
  select
    n.QuestionId,
    n.CreationDate,
    n.QualityScore,
    n.QualityRank,
    n.ViewCount,
    n.Score,
    avg(n.QualityScore) over (order by n.CreationDate rows between 99 preceding and current row) as MovAvgQuality_100,
    sum(n.ViewCount) over (order by n.CreationDate rows between 99 preceding and current row) as MovSumViews_100,
    stddev_pop(n.Score) over (order by n.CreationDate rows between 99 preceding and current row) as MovStdScore_100
  from null_exercises n
),
duplicates_as_correlated as (
  select
    rq.QuestionId,
    (select count(*) from PostLinks pl where pl.PostId = rq.QuestionId and pl.LinkTypeId = 3) as DupCountCorrelated
  from recent_questions rq
)
select
  n.QuestionId,
  n.CreationDate,
  n.Score,
  n.ViewCount,
  n.AnswerCount,
  n.PosAnswerCount,
  n.NegAnswerCount,
  n.UpVotesCnt,
  n.DownVotesCnt,
  n.FavoriteCnt,
  n.CommentCount,
  n.PosComments,
  n.SecToFirstAnswer,
  n.SecToLastComment,
  n.AskerReputation,
  n.AskerGold, n.AskerSilver, n.AskerBronze, n.AskerAgeDays,
  n.TagCount,
  n.DupCount,
  n.LinkedCount,
  n.FirstClosedAt,
  n.LastReopenedAt,
  n.CloseEvents,
  n.ReopenEvents,
  n.SelfAnswered,
  n.QualityScore,
  n.QualityRank,
  n.QualityPercentileLow,
  n.QualityPercentileHigh,
  n.NullableFlag,
  n.AskerReputationCoerced,
  n.SecToFirstAnswerNullAsNeg1,
  r.MovAvgQuality_100,
  r.MovSumViews_100,
  r.MovStdScore_100,
  dac.DupCountCorrelated,
  case
    when coalesce(n.TagCount,0) = 0 then 'untagged'
    when n.TagCount = 1 then 'single-tag'
    when n.TagCount between 2 and 3 then 'multi-tag'
    else 'many-tags'
  end as TagBucket,
  case
    when n.QualityScore is null then 'unknown'
    when n.QualityPercentileHigh >= 0.95 then 'top-5%'
    when n.QualityPercentileHigh >= 0.90 then 'top-10%'
    when n.QualityPercentileHigh >= 0.75 then 'top-25%'
    when n.QualityPercentileHigh >= 0.50 then 'top-50%'
    else 'bottom-50%'
  end as QualityTier
from null_exercises n
left join rolling r on r.QuestionId = n.QuestionId
left join duplicates_as_correlated dac on dac.QuestionId = n.QuestionId
where
  (
    (n.Score >= 0 and coalesce(n.DownVotesCnt,0) <= 5)
    or
    (n.Score < 0 and coalesce(n.UpVotesCnt,0) >= 2 and n.AnswerCount >= 1)
  )
  and (
    n.FirstClosedAt is null
    or n.ReopenEvents > 0
    or (n.DupCount = 0 and n.LinkedCount >= 1)
  )
  and (
    n.QualityScore is null
    or n.QualityScore >= (
      select avg(qq.QualityScore) + stddev_pop(qq.QualityScore)
      from quality_score qq
    )
    or n.AskerReputation >= (
      select percentile_disc(0.9) within group (order by Reputation)
      from Users
    )
  )
order by
  n.QualityRank nulls last,
  n.ViewCount desc nulls last,
  n.Score desc nulls last
limit 500;