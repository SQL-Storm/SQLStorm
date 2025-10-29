-- {"query": "654.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3236}
with
q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate as QuestionCreationDate,
    p.Score as QuestionScore,
    p.ViewCount,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) as TagCount
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select
    a.ParentId as QuestionId,
    a.Id as AnswerId,
    a.OwnerUserId as AnswerOwnerId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreationDate,
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn_score_desc,
    row_number() over (partition by a.ParentId order by a.CreationDate asc) as rn_oldest
  from Posts a
  where a.PostTypeId = 2
),
agg_ans as (
  select
    QuestionId,
    count(*) as AnswersTotal,
    sum(case when AnswerScore > 0 then 1 else 0 end) as AnswersPositive,
    avg(cast(AnswerScore as numeric)) as AvgAnswerScore,
    max(AnswerScore) as MaxAnswerScore,
    min(AnswerScore) as MinAnswerScore,
    min(AnswerCreationDate) as FirstAnswerDate,
    max(AnswerCreationDate) as LastAnswerDate
  from a
  group by QuestionId
),
best_ans as (
  select QuestionId, AnswerId as TopScoredAnswerId
  from a
  where rn_score_desc = 1
),
oldest_ans as (
  select QuestionId, AnswerId as FirstAnswerId, AnswerCreationDate
  from a
  where rn_oldest = 1
),
accepted as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.Tags,
    q.TagCount,
    q.AnswerCount,
    case when q.AnswerCount = 0 then null else 1 end as HasAnswersFlag,
    p2.Id as AcceptedAnswerId,
    p2.Score as AcceptedAnswerScore,
    p2.CreationDate as AcceptedAnswerDate
  from q
  left join Posts p2 on p2.Id = (
    select px.AcceptedAnswerId from Posts px where px.Id = q.QuestionId
  )
),
votes_q as (
  select
    v.PostId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyAmountTotal
  from Votes v
  join Posts p on p.Id = v.PostId and p.PostTypeId = 1
  group by v.PostId
),
votes_a as (
  select
    a.ParentId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as AnsUpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as AnsDownVotes
  from Posts a
  left join Votes v on v.PostId = a.Id
  where a.PostTypeId = 2
  group by a.ParentId
),
comments_q as (
  select
    c.PostId as QuestionId,
    count(*) as CommentCountQ,
    max(c.CreationDate) as LastCommentDateQ,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveCommentsQ
  from Comments c
  join Posts p on p.Id = c.PostId and p.PostTypeId = 1
  group by c.PostId
),
comments_a as (
  select
    a.ParentId as QuestionId,
    count(*) as CommentCountA,
    max(c.CreationDate) as LastCommentDateA
  from Posts a
  left join Comments c on c.PostId = a.Id
  where a.PostTypeId = 2
  group by a.ParentId
),
hist as (
  select
    ph.PostId as QuestionId,
    sum(case when ph.PostHistoryTypeId in (5,6,4) then 1 else 0 end) as EditEvents,
    sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotesEvents,
    sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenEvents,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditDate
  from PostHistory ph
  join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
  group by ph.PostId
),
dupes as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks
  from PostLinks pl
  group by pl.PostId
),
tag_expansion as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as tag
  from q
  where q.Tags is not null and length(q.Tags) > 2
),
tag_stats as (
  select
    te.QuestionId,
    count(*) as DistinctTagCount,
    sum(t.Count) as SumTagUsage,
    max(t.Count) as MaxTagUsage,
    min(t.Count) as MinTagUsage
  from tag_expansion te
  left join Tags t on lower(t.TagName) = lower(te.tag)
  group by te.QuestionId
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate as UserCreationDate,
    coalesce(u.Location, '') as Location,
    length(coalesce(u.AboutMe,'')) as AboutLen,
    u.UpVotes as UserUpVotes,
    u.DownVotes as UserDownVotes,
    u.Views as ProfileViews
  from Users u
),
badge_stats as (
  select
    b.UserId,
    count(*) as BadgesTotal,
    sum(case when b.Class = 1 then 1 else 0 end) as Gold,
    sum(case when b.Class = 2 then 1 else 0 end) as Silver,
    sum(case when b.Class = 3 then 1 else 0 end) as Bronze,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
accepted_delta as (
  select
    e.QuestionId,
    case
      when e.AcceptedAnswerDate is null then null
      else cast(extract(epoch from (e.AcceptedAnswerDate - e.QuestionCreationDate)) as bigint)
    end as SecondsToAccept
  from accepted e
),
answer_speeds as (
  select
    q.QuestionId,
    case when oa.AnswerCreationDate is null then null else cast(extract(epoch from (oa.AnswerCreationDate - q.QuestionCreationDate)) as bigint) end as SecondsToFirstAnswer,
    case when ba.AnswerCreationDate is null then null else cast(extract(epoch from (ba.AnswerCreationDate - q.QuestionCreationDate)) as bigint) end as SecondsToTopScoredAnswer
  from q
  left join oldest_ans oa on oa.QuestionId = q.QuestionId
  left join a ba on ba.QuestionId = q.QuestionId and ba.rn_score_desc = 1
),
activity as (
  select
    q.QuestionId,
    p.LastActivityDate,
    p.LastEditDate
  from q
  join Posts p on p.Id = q.QuestionId
),
normalized as (
  select
    e.QuestionId,
    e.Title,
    e.Tags,
    e.TagCount,
    e.QuestionScore,
    e.ViewCount,
    e.AnswerCount,
    coalesce(ag.AnswersTotal, 0) as AnswersTotal,
    coalesce(ag.AnswersPositive, 0) as AnswersPositive,
    cast(coalesce(ag.AvgAnswerScore, 0) as numeric(12,4)) as AvgAnswerScore,
    ag.MaxAnswerScore,
    ag.MinAnswerScore,
    e.AcceptedAnswerId,
    e.AcceptedAnswerScore,
    e.AcceptedAnswerDate,
    ad.SecondsToAccept,
    sp.SecondsToFirstAnswer,
    sp.SecondsToTopScoredAnswer,
    vq.UpVotes as QUpVotes,
    vq.DownVotes as QDownVotes,
    vq.Favorites as QFavorites,
    vq.BountyAmountTotal as QBounty,
    va.AnsUpVotes,
    va.AnsDownVotes,
    cq.CommentCountQ,
    ca.CommentCountA,
    greatest(coalesce(cq.LastCommentDateQ, timestamp 'epoch'), coalesce(ca.LastCommentDateA, timestamp 'epoch')) as LastCommentDateAny,
    h.EditEvents,
    h.CloseVotesEvents,
    h.ReopenEvents,
    h.FirstEditDate,
    d.DuplicateLinks,
    d.LinkedLinks,
    ts.DistinctTagCount,
    ts.SumTagUsage,
    ts.MaxTagUsage,
    ts.MinTagUsage,
    us.UserId as OwnerUserId,
    us.Reputation as OwnerReputation,
    us.Location as OwnerLocation,
    us.AboutLen as OwnerAboutLength,
    bs.BadgesTotal,
    bs.Gold,
    bs.Silver,
    bs.Bronze,
    bs.LastBadgeDate,
    act.LastActivityDate,
    act.LastEditDate
  from accepted e
  left join agg_ans ag on ag.QuestionId = e.QuestionId
  left join votes_q vq on vq.QuestionId = e.QuestionId
  left join votes_a va on va.QuestionId = e.QuestionId
  left join comments_q cq on cq.QuestionId = e.QuestionId
  left join comments_a ca on ca.QuestionId = e.QuestionId
  left join hist h on h.QuestionId = e.QuestionId
  left join dupes d on d.QuestionId = e.QuestionId
  left join tag_stats ts on ts.QuestionId = e.QuestionId
  left join Users u on u.Id = e.OwnerUserId
  left join user_stats us on us.UserId = u.Id
  left join badge_stats bs on bs.UserId = u.Id
  left join accepted_delta ad on ad.QuestionId = e.QuestionId
  left join answer_speeds sp on sp.QuestionId = e.QuestionId
  left join activity act on act.QuestionId = e.QuestionId
),
ranked as (
  select
    n.QuestionId,
    n.Title,
    n.Tags,
    n.TagCount,
    n.QuestionScore,
    n.ViewCount,
    n.AnswerCount,
    n.AnswersTotal,
    n.AnswersPositive,
    n.AvgAnswerScore,
    n.MaxAnswerScore,
    n.MinAnswerScore,
    n.AcceptedAnswerId,
    n.AcceptedAnswerScore,
    n.AcceptedAnswerDate,
    n.SecondsToAccept,
    n.SecondsToFirstAnswer,
    n.SecondsToTopScoredAnswer,
    n.QUpVotes,
    n.QDownVotes,
    n.QFavorites,
    n.QBounty,
    n.AnsUpVotes,
    n.AnsDownVotes,
    n.CommentCountQ,
    n.CommentCountA,
    n.LastCommentDateAny,
    n.EditEvents,
    n.CloseVotesEvents,
    n.ReopenEvents,
    n.FirstEditDate,
    n.DuplicateLinks,
    n.LinkedLinks,
    n.DistinctTagCount,
    n.SumTagUsage,
    n.MaxTagUsage,
    n.MinTagUsage,
    n.OwnerUserId,
    n.OwnerReputation,
    n.OwnerLocation,
    n.OwnerAboutLength,
    n.BadgesTotal,
    n.Gold,
    n.Silver,
    n.Bronze,
    n.LastBadgeDate,
    n.LastActivityDate,
    n.LastEditDate,
    row_number() over (order by coalesce(n.QFavorites,0) desc, coalesce(n.ViewCount,0) desc, n.QuestionScore desc) as rn_popular,
    percent_rank() over (order by coalesce(n.SecondsToFirstAnswer, 9223372036854775807)) as pct_speed_first_answer,
    dense_rank() over (partition by case when n.TagCount >= 5 then 'many' when n.TagCount >= 3 then 'mid' else 'few' end order by coalesce(n.QUpVotes,0) desc) as dr_by_tagload,
    coalesce(n.QUpVotes,0) - coalesce(n.QDownVotes,0) as NetQVotes,
    case when n.AnswersTotal = 0 then null else (cast(coalesce(n.AnsUpVotes,0) as numeric) / nullif(n.AnswersTotal,0)) end as AvgAnsUpVotesPerAnswer
  from normalized n
),
thresholds as (
  select
    avg(ViewCount) as avg_views,
    percentile_cont(0.9) within group (order by coalesce(QFavorites,0)) as p90_favs,
    percentile_cont(0.5) within group (order by coalesce(SecondsToFirstAnswer,0)) as p50_first_ans_secs
  from ranked
),
flagged as (
  select
    r.QuestionId,
    r.Title,
    r.Tags,
    r.TagCount,
    r.DistinctTagCount,
    r.SumTagUsage,
    r.QuestionScore,
    r.NetQVotes,
    r.QUpVotes,
    r.QDownVotes,
    r.QFavorites,
    r.QBounty,
    r.ViewCount,
    r.AnswerCount,
    r.AnswersTotal,
    r.AnswersPositive,
    r.AvgAnswerScore,
    r.MaxAnswerScore,
    r.MinAnswerScore,
    r.AcceptedAnswerId,
    r.AcceptedAnswerScore,
    r.SecondsToAccept,
    r.SecondsToFirstAnswer,
    r.SecondsToTopScoredAnswer,
    r.CommentCountQ,
    r.CommentCountA,
    r.EditEvents,
    r.CloseVotesEvents,
    r.ReopenEvents,
    r.DuplicateLinks,
    r.LinkedLinks,
    r.OwnerUserId,
    r.OwnerReputation,
    r.OwnerLocation,
    r.OwnerAboutLength,
    r.BadgesTotal,
    r.Gold,
    r.Silver,
    r.Bronze,
    r.LastActivityDate,
    r.LastEditDate,
    r.FirstEditDate,
    r.rn_popular,
    r.pct_speed_first_answer,
    r.dr_by_tagload,
    t.avg_views,
    t.p90_favs,
    t.p50_first_ans_secs,
    case when r.ViewCount > t.avg_views and coalesce(r.QFavorites,0) >= t.p90_favs then 1 else 0 end as IsHighlyPopular,
    case when coalesce(r.SecondsToFirstAnswer, 9223372036854775807) <= t.p50_first_ans_secs then 1 else 0 end as IsFastAnswered,
    case when r.EditEvents >= 5 or r.CloseVotesEvents > 0 then 1 else 0 end as IsContentious
  from ranked r
  cross join thresholds t
)
select
  f.QuestionId,
  coalesce(nullif(trim(both from f.Title), ''), concat('[untitled-', f.QuestionId, ']')) as TitleSafe,
  f.Tags,
  f.TagCount,
  f.DistinctTagCount,
  f.SumTagUsage,
  f.QuestionScore,
  f.NetQVotes,
  f.QUpVotes,
  f.QDownVotes,
  f.QFavorites,
  f.QBounty,
  f.ViewCount,
  f.AnswerCount,
  f.AnswersTotal,
  f.AnswersPositive,
  f.AvgAnswerScore,
  f.MaxAnswerScore,
  f.MinAnswerScore,
  f.AcceptedAnswerId,
  f.AcceptedAnswerScore,
  f.SecondsToAccept,
  f.SecondsToFirstAnswer,
  f.SecondsToTopScoredAnswer,
  f.CommentCountQ,
  f.CommentCountA,
  f.EditEvents,
  f.CloseVotesEvents,
  f.ReopenEvents,
  f.DuplicateLinks,
  f.LinkedLinks,
  f.OwnerUserId,
  f.OwnerReputation,
  f.OwnerLocation,
  f.BadgesTotal,
  f.Gold,
  f.Silver,
  f.Bronze,
  f.LastActivityDate,
  f.LastEditDate,
  f.FirstEditDate,
  f.IsHighlyPopular,
  f.IsFastAnswered,
  f.IsContentious,
  f.rn_popular,
  f.pct_speed_first_answer,
  f.dr_by_tagload
from flagged f
where
  coalesce(f.ViewCount,0) > 0
  and (
    f.IsHighlyPopular = 1
    or (f.IsFastAnswered = 1 and coalesce(f.AnswersPositive,0) >= 1)
    or (f.IsContentious = 1 and coalesce(f.DuplicateLinks,0) > 0)
  )
  and not exists (
    select 1
    from PostHistory ph
    where ph.PostId = f.QuestionId
      and ph.PostHistoryTypeId in (12)
  )
order by
  f.IsHighlyPopular desc,
  f.rn_popular asc,
  f.SecondsToFirstAnswer nulls last
limit 500;