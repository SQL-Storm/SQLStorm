-- {"query": "412.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2863}
with recent_questions as (
  select
    q.Id as QuestionId,
    q.CreationDate,
    q.OwnerUserId,
    q.Score,
    q.ViewCount,
    q.Title,
    q.Tags,
    q.ClosedDate,
    q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1
    and q.CreationDate >= (
      select date_trunc('month', max(CreationDate)) - interval '12 months'
      from Posts
      where PostTypeId = 1
    )
),
tag_expansion as (
  select
    rq.QuestionId,
    lower(trim(t.tag)) as tag
  from recent_questions rq
  cross join lateral (
    select unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) as tag
  ) t
),
tag_meta as (
  select
    te.QuestionId,
    te.tag,
    coalesce(tt.Count, 0) as GlobalTagCount,
    coalesce(case when tt.IsModeratorOnly is not null then cast(tt.IsModeratorOnly as integer) else 0 end, 0) as IsModOnly,
    coalesce(case when tt.IsRequired is not null then cast(tt.IsRequired as integer) else 0 end, 0) as IsRequired
  from tag_expansion te
  left join Tags tt
    on tt.TagName = te.tag
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesCount,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesCount,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoritesCount,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal
  from Votes v
  group by v.PostId
),
answers_agg as (
  select
    a.ParentId as QuestionId,
    count(*) as AnswerCount,
    max(a.Score) as MaxAnswerScore,
    sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers
  from Posts a
  where a.PostTypeId = 2
  group by a.ParentId
),
accepted_answer_stats as (
  select
    q.QuestionId,
    aa.Id as AcceptedAnswerId,
    aa.Score as AcceptedAnswerScore,
    aa.CreationDate as AcceptedAnswerDate,
    extract(epoch from (aa.CreationDate - rq.CreationDate))/3600.0 as HoursToAccept
  from recent_questions rq
  join Posts aa
    on aa.Id = rq.AcceptedAnswerId
  right join recent_questions q
    on q.QuestionId = rq.QuestionId
),
comments_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    max(c.Score) as MaxCommentScore,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments
  from Comments c
  group by c.PostId
),
edits_agg as (
  select
    ph.PostId,
    sum(case when ph.PostHistoryTypeId in (4,5,6,7,8,9,24) then 1 else 0 end) as EditEvents,
    sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotesLike,
    max(case when ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35) then ph.CreationDate end) as LastModerationEvent
  from PostHistory ph
  group by ph.PostId
),
closures as (
  select
    rq.QuestionId,
    min(ph.CreationDate) as FirstCloseDate,
    max(ph.CreationDate) as LastCloseDate,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents
  from recent_questions rq
  left join PostHistory ph
    on ph.PostId = rq.QuestionId
   and ph.PostHistoryTypeId = 10
  group by rq.QuestionId
),
duplicates as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
    min(pl.CreationDate) as FirstLinkDate
  from PostLinks pl
  group by pl.PostId
),
owner_stats as (
  select
    u.Id as OwnerUserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) as TotalQuestions,
    coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) as TotalAnswers,
    count(distinct b.Name) as DistinctBadges
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
quality_score as (
  select
    rq.QuestionId,
    (coalesce(va.UpVotesCount,0) - coalesce(va.DownVotesCount,0)) * 2
    + coalesce(va.FavoritesCount,0) * 3
    + coalesce(ans.MaxAnswerScore,0) * 1.5
    + least(coalesce(ans.AnswerCount,0), 10) * 0.8
    + case when aa.AcceptedAnswerId is not null then 5 else 0 end
    + case when cl.CloseEvents > 0 then -10 else 0 end
    + greatest(0, 10 - coalesce(ed.EditEvents,0)) * 0.3
    + case when dm.DuplicateLinks > 0 then -5 else 0 end
    + least(coalesce(va.BountyTotal,0)/50.0, 10)
    as CompositeQuality
  from recent_questions rq
  left join votes_agg va on va.PostId = rq.QuestionId
  left join answers_agg ans on ans.QuestionId = rq.QuestionId
  left join accepted_answer_stats aa on aa.QuestionId = rq.QuestionId
  left join edits_agg ed on ed.PostId = rq.QuestionId
  left join duplicates dm on dm.QuestionId = rq.QuestionId
  left join closures cl on cl.QuestionId = rq.QuestionId
),
tag_rollup as (
  select
    tm.QuestionId,
    count(*) as TagCount,
    sum(case when tm.GlobalTagCount >= 10000 then 1 else 0 end) as PopularTags,
    sum(tm.IsModOnly) as ModOnlyTags,
    sum(tm.IsRequired) as RequiredTags
  from tag_meta tm
  group by tm.QuestionId
),
per_user_recent as (
  select
    rq.OwnerUserId,
    count(*) as RecentQuestionCount,
    avg(rq.Score) as AvgRecentQuestionScore,
    percentile_cont(0.5) within group (order by rq.ViewCount) as MedianRecentViews
  from recent_questions rq
  where rq.OwnerUserId is not null
  group by rq.OwnerUserId
),
dense_ranked as (
  select
    rq.QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    qs.CompositeQuality,
    rank() over (order by qs.CompositeQuality desc NULLS LAST, rq.ViewCount desc NULLS LAST) as rnk,
    dense_rank() over (partition by date_trunc('month', rq.CreationDate) order by qs.CompositeQuality desc NULLS LAST, rq.Score desc NULLS LAST) as month_dense_rnk
  from recent_questions rq
  left join quality_score qs on qs.QuestionId = rq.QuestionId
),
final_enriched as (
  select
    dr.QuestionId,
    dr.Title,
    dr.OwnerUserId,
    dr.CreationDate,
    dr.Score,
    dr.ViewCount,
    dr.CompositeQuality,
    dr.rnk,
    dr.month_dense_rnk,
    coalesce(va.UpVotesCount,0) as UpVotesCount,
    coalesce(va.DownVotesCount,0) as DownVotesCount,
    coalesce(va.FavoritesCount,0) as FavoritesCount,
    coalesce(va.BountyTotal,0) as BountyTotal,
    coalesce(ans.AnswerCount,0) as AnswerCount,
    coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(ans.PositiveAnswers,0) as PositiveAnswers,
    coalesce(ca.CommentCount,0) as CommentCount,
    coalesce(ca.MaxCommentScore,0) as MaxCommentScore,
    coalesce(ca.PositiveComments,0) as PositiveComments,
    coalesce(ed.EditEvents,0) as EditEvents,
    ed.LastModerationEvent,
    cl.FirstCloseDate,
    cl.LastCloseDate,
    coalesce(cl.CloseEvents,0) as CloseEvents,
    coalesce(dm.DuplicateLinks,0) as DuplicateLinks,
    coalesce(dm.LinkedLinks,0) as LinkedLinks,
    tr.TagCount,
    tr.PopularTags,
    tr.ModOnlyTags,
    tr.RequiredTags,
    aa.AcceptedAnswerId,
    aa.AcceptedAnswerScore,
    round(coalesce(aa.HoursToAccept, null), 2) as HoursToAccept
  from dense_ranked dr
  left join votes_agg va on va.PostId = dr.QuestionId
  left join answers_agg ans on ans.QuestionId = dr.QuestionId
  left join comments_agg ca on ca.PostId = dr.QuestionId
  left join edits_agg ed on ed.PostId = dr.QuestionId
  left join closures cl on cl.QuestionId = dr.QuestionId
  left join duplicates dm on dm.QuestionId = dr.QuestionId
  left join tag_rollup tr on tr.QuestionId = dr.QuestionId
  left join accepted_answer_stats aa on aa.QuestionId = dr.QuestionId
)
select
  fe.QuestionId,
  coalesce(fe.Title, '(no title)') as Title,
  fe.OwnerUserId,
  u.DisplayName as OwnerDisplayName,
  u.Location as OwnerLocation,
  os.Reputation as OwnerReputation,
  os.TotalQuestions,
  os.TotalAnswers,
  os.DistinctBadges,
  pr.RecentQuestionCount,
  round(coalesce(pr.AvgRecentQuestionScore,0), 2) as AvgRecentQuestionScore,
  pr.MedianRecentViews,
  fe.CreationDate,
  fe.Score,
  fe.ViewCount,
  fe.UpVotesCount,
  fe.DownVotesCount,
  fe.FavoritesCount,
  fe.BountyTotal,
  fe.AnswerCount,
  fe.MaxAnswerScore,
  fe.PositiveAnswers,
  fe.CommentCount,
  fe.MaxCommentScore,
  fe.PositiveComments,
  fe.EditEvents,
  fe.LastModerationEvent,
  fe.FirstCloseDate,
  fe.LastCloseDate,
  fe.CloseEvents,
  fe.DuplicateLinks,
  fe.LinkedLinks,
  fe.TagCount,
  fe.PopularTags,
  fe.ModOnlyTags,
  fe.RequiredTags,
  fe.AcceptedAnswerId,
  fe.AcceptedAnswerScore,
  fe.HoursToAccept,
  fe.CompositeQuality,
  fe.rnk as GlobalRank,
  fe.month_dense_rnk as MonthlyDenseRank,
  case
    when fe.CompositeQuality is null then 'unknown'
    when fe.CompositeQuality >= 40 then 'elite'
    when fe.CompositeQuality >= 25 then 'great'
    when fe.CompositeQuality >= 12 then 'good'
    when fe.CompositeQuality >= 4 then 'ok'
    else 'low'
  end as QualityBucket,
  case
    when fe.TagCount is null then 'untagged'
    when fe.ModOnlyTags > 0 then 'mod-heavy'
    when fe.PopularTags >= greatest(1, fe.TagCount/2) then 'popular'
    else 'niche'
  end as TagProfile,
  trim(both ' ' from coalesce(u.WebsiteUrl, '')) as OwnerWebsite,
  left(coalesce(u.AboutMe, ''), 120) as OwnerAboutSnippet
from final_enriched fe
left join Users u on u.Id = fe.OwnerUserId
left join owner_stats os on os.OwnerUserId = fe.OwnerUserId
left join per_user_recent pr on pr.OwnerUserId = fe.OwnerUserId
where
  (fe.CompositeQuality is null or fe.CompositeQuality >= 0 or fe.AnswerCount > 0)
  and coalesce(fe.CloseEvents,0) <= 5
  and (
    fe.TagCount is null
    or fe.PopularTags >= 0
    or (fe.ModOnlyTags = 0 and fe.RequiredTags >= 0)
  )
  and (
    u.Reputation is null
    or (u.Reputation >= 1 and (u.DownVotes is null or u.DownVotes >= 0))
  )
  and (
    fe.LastModerationEvent is null
    or fe.LastModerationEvent >= fe.CreationDate - interval '30 days'
    or fe.EditEvents >= 0
  )
order by
  QualityBucket desc,
  fe.CompositeQuality desc NULLS LAST,
  fe.ViewCount desc NULLS LAST,
  fe.Score desc NULLS LAST
limit 500;