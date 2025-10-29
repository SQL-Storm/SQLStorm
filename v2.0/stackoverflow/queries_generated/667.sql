-- {"query": "667.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3220} 
with recent_q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    coalesce(p.ViewCount, 0) as ViewCount,
    coalesce(p.Score, 0) as Score,
    p.Tags,
    cardinality(nullif(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><'), array[]::varchar[])) as TagCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select date_trunc('month', max(CreationDate)) - interval '6 months' from Posts where PostTypeId = 1)
),
answers as (
  select
    a.ParentId as QuestionId,
    count(*) filter (where a.CreationDate <= rq.CreationDate + interval '14 days') as AnswersInTwoWeeks,
    count(*) as TotalAnswers,
    max(a.Score) as MaxAnswerScore,
    avg(a.Score) as AvgAnswerScore
  from Posts a
  join recent_q rq on rq.QuestionId = a.ParentId
  where a.PostTypeId = 2
  group by a.ParentId
),
accepted as (
  select
    rq.QuestionId,
    case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    aa.Score as AcceptedScore,
    aa.CreationDate as AcceptedDate
  from recent_q rq
  left join Posts p on p.Id = rq.QuestionId
  left join Posts aa on aa.Id = p.AcceptedAnswerId
),
votes_rollup as (
  select
    v.PostId as QuestionId,
    count(*) filter (where v.VoteTypeId = 2) as UpVotes,
    count(*) filter (where v.VoteTypeId = 3) as DownVotes,
    count(*) filter (where v.VoteTypeId = 5) as Favorites,
    sum(coalesce(v.BountyAmount,0)) filter (where v.VoteTypeId in (8,9)) as BountyAmount
  from Votes v
  where exists (select 1 from recent_q rq where rq.QuestionId = v.PostId)
  group by v.PostId
),
comment_stats as (
  select
    c.PostId as QuestionId,
    count(*) as CommentCount,
    max(c.Score) as MaxCommentScore,
    avg(c.Score) as AvgCommentScore
  from Comments c
  where exists (select 1 from recent_q rq where rq.QuestionId = c.PostId)
  group by c.PostId
),
tag_expanded as (
  select
    rq.QuestionId,
    lower(trim(t)) as tag
  from recent_q rq
  cross join lateral unnest(nullif(string_to_array(substring(rq.Tags, 2, greatest(length(rq.Tags)-2,0)), '><'), array[]::varchar[])) as t
),
tag_quality as (
  select
    te.QuestionId,
    avg(least(greatest(log(10, nullif(tg.Count,0)), 0), 6)) as AvgTagLogCount,
    count(*) filter (where tg.IsModeratorOnly) as ModeratorOnlyTagCount,
    count(*) filter (where tg.IsRequired) as RequiredTagCount
  from tag_expanded te
  left join Tags tg on tg.TagName = te.tag
  group by te.QuestionId
),
link_dupes as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedCount
  from PostLinks pl
  where exists (select 1 from recent_q rq where rq.QuestionId = pl.PostId)
  group by pl.PostId
),
close_events as (
  select
    ph.PostId as QuestionId,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstCloseDate,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesEvents,
    count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
    count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20)) as ModActionEvents,
    max(case
      when ph.PostHistoryTypeId = 10 then
        nullif(regexp_replace(ph.Comment, '[^0-9]', '', 'g'), '')
      else null
    end)::int as AnyCloseReasonId
  from PostHistory ph
  where exists (select 1 from recent_q rq where rq.QuestionId = ph.PostId)
  group by ph.PostId
),
user_activity as (
  select
    u.Id as UserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    date_part('day', now() - u.CreationDate) as AccountAgeDays,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    count(*) as TotalBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate
),
user_posts as (
  select
    p.OwnerUserId as UserId,
    count(*) filter (where p.PostTypeId = 1) as QCount,
    count(*) filter (where p.PostTypeId = 2) as ACount,
    avg(nullif(p.Score,0)) as AvgNonZeroScore,
    max(p.Score) as MaxScore,
    sum(coalesce(p.ViewCount,0)) as SumViews
  from Posts p
  group by p.OwnerUserId
),
ranked_questions as (
  select
    rq.*,
    row_number() over (partition by date_trunc('month', rq.CreationDate) order by rq.Score desc nulls last, rq.ViewCount desc nulls last, rq.QuestionId) as RankInMonth,
    dense_rank() over (order by rq.Score desc nulls last, rq.ViewCount desc nulls last) as DenseRankAll
  from recent_q rq
),
quality_score as (
  select
    rq.QuestionId,
    (coalesce(rq.Score,0) * 2
      + coalesce(vr.UpVotes,0) * 1
      - coalesce(vr.DownVotes,0) * 2
      + least(coalesce(rq.ViewCount,0) / nullif(10 + rq.TagCount,0), 500)
      + coalesce(ans.TotalAnswers,0) * 1.5
      + coalesce(ans.MaxAnswerScore,0) * 0.5
      + coalesce(acc.HasAccepted,0) * 5
      + case when acc.AcceptedDate is not null and acc.AcceptedDate <= rq.CreationDate + interval '7 days' then 3 else 0 end
      + coalesce(cs.CommentCount,0) * 0.25
      - coalesce(le.DuplicateLinks,0) * 4
      - case when ce.FirstCloseDate is not null then 10 else 0 end
      + coalesce(tq.AvgTagLogCount,0) * 1.2
    )::numeric(18,4) as CompositeQuality
  from recent_q rq
  left join answers ans on ans.QuestionId = rq.QuestionId
  left join accepted acc on acc.QuestionId = rq.QuestionId
  left join votes_rollup vr on vr.QuestionId = rq.QuestionId
  left join comment_stats cs on cs.QuestionId = rq.QuestionId
  left join link_dupes le on le.QuestionId = rq.QuestionId
  left join close_events ce on ce.QuestionId = rq.QuestionId
  left join tag_quality tq on tq.QuestionId = rq.QuestionId
),
question_user as (
  select
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.TagCount,
    rq.Tags,
    qp.DisplayName,
    qp.OwnerUserId,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalBadges,
    up.QCount,
    up.ACount,
    up.AvgNonZeroScore,
    up.MaxScore as UserMaxPostScore,
    up.SumViews as UserSumViews
  from recent_q rq
  left join Posts qp on qp.Id = rq.QuestionId
  left join user_activity ua on ua.UserId = qp.OwnerUserId
  left join user_posts up on up.UserId = qp.OwnerUserId
),
final_union as (
  select
    qu.QuestionId,
    qu.Title,
    qu.CreationDate,
    qu.ViewCount,
    qu.Score,
    qu.TagCount,
    qu.Tags,
    qu.DisplayName,
    qu.OwnerUserId,
    qu.Reputation,
    qu.GoldBadges,
    qu.SilverBadges,
    qu.BronzeBadges,
    qu.TotalBadges,
    qu.QCount,
    qu.ACount,
    qu.AvgNonZeroScore,
    qu.UserMaxPostScore,
    qu.UserSumViews,
    coalesce(ans.TotalAnswers,0) as TotalAnswers,
    coalesce(ans.AnswersInTwoWeeks,0) as AnswersInTwoWeeks,
    coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(ans.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(acc.HasAccepted,0) as HasAccepted,
    coalesce(vr.UpVotes,0) as UpVotes,
    coalesce(vr.DownVotes,0) as DownVotes,
    coalesce(vr.Favorites,0) as Favorites,
    coalesce(vr.BountyAmount,0) as BountyAmount,
    coalesce(cs.CommentCount,0) as CommentCount,
    coalesce(le.DuplicateLinks,0) as DuplicateLinks,
    coalesce(le.LinkedCount,0) as LinkedCount,
    ce.FirstCloseDate,
    coalesce(ce.CloseVotesEvents,0) as CloseVotesEvents,
    coalesce(ce.ReopenEvents,0) as ReopenEvents,
    coalesce(ce.ModActionEvents,0) as ModActionEvents,
    ce.AnyCloseReasonId,
    qs.CompositeQuality,
    rq.RankInMonth,
    rq.DenseRankAll
  from question_user qu
  join ranked_questions rq on rq.QuestionId = qu.QuestionId
  left join answers ans on ans.QuestionId = qu.QuestionId
  left join accepted acc on acc.QuestionId = qu.QuestionId
  left join votes_rollup vr on vr.QuestionId = qu.QuestionId
  left join comment_stats cs on cs.QuestionId = qu.QuestionId
  left join link_dupes le on le.QuestionId = qu.QuestionId
  left join close_events ce on ce.QuestionId = qu.QuestionId
  left join quality_score qs on qs.QuestionId = qu.QuestionId
  union all
  select
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.TagCount,
    rq.Tags,
    null, null, null, null, null, null, null, null, null, null, null, null,
    null, null, null, null, null, null, null, null, null, null, qs.CompositeQuality, rq.RankInMonth, rq.DenseRankAll
  from ranked_questions rq
  left join quality_score qs on qs.QuestionId = rq.QuestionId
  where rq.Score is null or rq.ViewCount is null
),
scored as (
  select
    f.*,
    row_number() over (order by f.CompositeQuality desc nulls last, f.ViewCount desc nulls last, f.Score desc nulls last, f.QuestionId) as GlobalRowNum,
    ntile(10) over (order by f.CompositeQuality desc nulls last) as QualityDecile,
    case
      when f.CompositeQuality is null then 'Unknown'
      when f.CompositeQuality >= percentile_cont(0.9) within group (order by f.CompositeQuality) over () then 'Top10%'
      when f.CompositeQuality >= percentile_cont(0.75) within group (order by f.CompositeQuality) over () then 'Top25%'
      when f.CompositeQuality >= percentile_cont(0.5) within group (order by f.CompositeQuality) over () then 'Top50%'
      else 'Lower50%'
    end as QualityBand
  from final_union f
),
filtered as (
  select *
  from scored
  where (TagCount is null or TagCount between 1 and 5)
    and (DownVotes is null or DownVotes <= UpVotes * 2 + 3)
    and (FirstCloseDate is null or FirstCloseDate > CreationDate + interval '2 hours')
)
select
  s.QuestionId,
  coalesce(s.Title, '(untitled)') as Title,
  s.CreationDate,
  coalesce(s.ViewCount, 0) as ViewCount,
  coalesce(s.Score, 0) as Score,
  s.TagCount,
  s.Tags,
  coalesce(s.DisplayName, '(anonymous)') as OwnerDisplayName,
  s.OwnerUserId,
  s.Reputation,
  s.GoldBadges,
  s.SilverBadges,
  s.BronzeBadges,
  s.TotalBadges,
  s.QCount,
  s.ACount,
  round(coalesce(s.AvgNonZeroScore,0)::numeric, 2) as AvgNonZeroScore,
  s.UserMaxPostScore,
  s.UserSumViews,
  s.TotalAnswers,
  s.AnswersInTwoWeeks,
  s.MaxAnswerScore,
  round(coalesce(s.AvgAnswerScore,0)::numeric,2) as AvgAnswerScore,
  s.HasAccepted,
  s.UpVotes,
  s.DownVotes,
  s.Favorites,
  s.BountyAmount,
  s.CommentCount,
  s.DuplicateLinks,
  s.LinkedCount,
  s.FirstCloseDate,
  s.CloseVotesEvents,
  s.ReopenEvents,
  s.ModActionEvents,
  s.AnyCloseReasonId,
  round(coalesce(s.CompositeQuality,0)::numeric,2) as CompositeQuality,
  s.RankInMonth,
  s.DenseRankAll,
  s.GlobalRowNum,
  s.QualityDecile,
  s.QualityBand
from filtered s
where coalesce(s.CompositeQuality, 0) >= (
  select percentile_cont(0.25) within group (order by coalesce(CompositeQuality,0)) from filtered
)
order by s.CompositeQuality desc nulls last, s.ViewCount desc nulls last, s.Score desc nulls last, s.QuestionId
limit 500;