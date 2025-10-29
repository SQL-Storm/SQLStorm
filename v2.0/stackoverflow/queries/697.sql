with
q as (
  select
    p.Id as QuestionId,
    p.CreationDate as QuestionCreationDate,
    p.OwnerUserId as QuestionOwnerId,
    p.Score as QuestionScore,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AcceptedAnswerId,
    coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select
    p.Id as AnswerId,
    p.ParentId as QuestionId,
    p.OwnerUserId as AnswerOwnerId,
    p.Score as AnswerScore,
    p.CreationDate as AnswerCreationDate
  from Posts p
  where p.PostTypeId = 2
),
q_stats as (
  select
    q.QuestionId,
    q.QuestionCreationDate,
    q.QuestionOwnerId,
    q.QuestionScore,
    q.ViewCount,
    q.Title,
    q.Tags,
    q.AcceptedAnswerId,
    q.AnswerCount,
    count(a.AnswerId) filter (where a.AnswerId is not null) as ActualAnswerCount,
    max(a.AnswerScore) as MaxAnswerScore,
    avg(a.AnswerScore) as AvgAnswerScore,
    min(a.AnswerCreationDate) as FirstAnswerDate,
    max(a.AnswerCreationDate) as LastAnswerDate
  from q
  left join a on a.QuestionId = q.QuestionId
  group by q.QuestionId, q.QuestionCreationDate, q.QuestionOwnerId, q.QuestionScore, q.ViewCount, q.Title, q.Tags, q.AcceptedAnswerId, q.AnswerCount
),
accepted as (
  select
    q.QuestionId,
    pa.Id as AcceptedAnswerId,
    pa.OwnerUserId as AcceptedOwnerId,
    pa.Score as AcceptedScore,
    pa.CreationDate as AcceptedCreationDate
  from q
  left join Posts pa on pa.Id = q.AcceptedAnswerId
),
votes as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyAmountTotal,
    count(*) as TotalVotes,
    min(v.CreationDate) as FirstVote,
    max(v.CreationDate) as LastVote
  from Votes v
  group by v.PostId
),
comments_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
    max(c.Score) as MaxCommentScore,
    min(c.CreationDate) as FirstCommentDate,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate as UserCreationDate,
    u.DisplayName,
    u.Location,
    u.UpVotes as UserUpVotes,
    u.DownVotes as UserDownVotes,
    u.Views as ProfileViews,
    count(b.Id) as BadgeCount,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    max(b.Date) as LastBadgeDate
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.Location, u.UpVotes, u.DownVotes, u.Views
),
q_badge_density as (
  select
    qs.QuestionId,
    us.BadgeCount,
    case when extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - us.UserCreationDate)) > 0
      then us.BadgeCount / extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - us.UserCreationDate))
      else null end as BadgesPerSecond
  from q_stats qs
  left join user_stats us on us.UserId = qs.QuestionOwnerId
),
dupes as (
  select pl.PostId as QuestionId, count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks
  from PostLinks pl
  group by pl.PostId
),
close_events as (
  select
    ph.PostId as QuestionId,
    sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotes,
    sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenVotes,
    max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as integer) else null end) as LastCloseReasonId,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,11)) as LastCloseOrReopenDate
  from PostHistory ph
  group by ph.PostId
),
tag_expansion as (
  select
    qs.QuestionId,
    unnest(string_to_array(substring(qs.Tags, 2, greatest(length(qs.Tags)-2,0)), '><')) as TagName
  from q_stats qs
  where qs.Tags is not null and qs.Tags like '<%>'
),
tag_rank as (
  select
    te.QuestionId,
    te.TagName,
    t.Count as GlobalTagCount,
    dense_rank() over (partition by te.QuestionId order by coalesce(t.Count,0) desc nulls last, te.TagName) as TagPopularityRank
  from tag_expansion te
  left join Tags t on lower(t.TagName) = lower(te.TagName)
),
q_windows as (
  select
    qs.QuestionId,
    qs.QuestionCreationDate,
    qs.QuestionOwnerId,
    qs.QuestionScore,
    qs.ViewCount,
    qs.Title,
    qs.Tags,
    qs.AcceptedAnswerId,
    qs.AnswerCount,
    row_number() over (order by coalesce(qs.ViewCount,0) desc, qs.QuestionScore desc, qs.QuestionId) as rn_by_popularity,
    ntile(10) over (order by coalesce(qs.ViewCount,0) desc) as view_ntile,
    sum(coalesce(vq.UpVotes,0)) over (order by qs.QuestionCreationDate rows between unbounded preceding and current row) as cum_upvotes_by_time,
    avg(coalesce(vq.UpVotes - vq.DownVotes,0)) over (partition by extract(year from qs.QuestionCreationDate)) as avg_net_votes_by_year
  from q_stats qs
  left join votes vq on vq.PostId = qs.QuestionId
),
answer_latency as (
  select
    qs.QuestionId,
    extract(epoch from (min(a.AnswerCreationDate) - qs.QuestionCreationDate)) as FirstAnswerLatencySeconds,
    extract(epoch from (max(a.AnswerCreationDate) - qs.QuestionCreationDate)) as LastAnswerLatencySeconds
  from q_stats qs
  left join a on a.QuestionId = qs.QuestionId
  group by qs.QuestionId, qs.QuestionCreationDate
),
accepted_latency as (
  select
    qs.QuestionId,
    extract(epoch from (acc.AcceptedCreationDate - qs.QuestionCreationDate)) as AcceptedLatencySeconds
  from q_stats qs
  left join accepted acc on acc.QuestionId = qs.QuestionId
),
quality_flags as (
  select
    qs.QuestionId,
    case
      when qs.QuestionScore >= 5 and coalesce(vq.UpVotes,0) >= 10 and coalesce(ca.CommentCount,0) >= 2 then 'High'
      when qs.QuestionScore <= 0 and coalesce(vq.DownVotes,0) >= 3 then 'Low'
      else 'Medium'
    end as QualityBucket,
    case
      when coalesce(qs.ViewCount,0) > 10000 and coalesce(qs.AnswerCount,0) >= 3 then 1 else 0
    end as IsPopularAnswered,
    case
      when acc.AcceptedAnswerId is null and coalesce(qs.AnswerCount,0) > 0 then 1 else 0
    end as HasAnswersNoAccepted
  from q_stats qs
  left join votes vq on vq.PostId = qs.QuestionId
  left join comments_agg ca on ca.PostId = qs.QuestionId
  left join accepted acc on acc.QuestionId = qs.QuestionId
),
calc as (
  select
    qw.QuestionId,
    qw.Title,
    qw.Tags,
    qw.QuestionScore,
    qw.ViewCount,
    qw.AnswerCount,
    coalesce(vq.UpVotes,0) as UpVotes,
    coalesce(vq.DownVotes,0) as DownVotes,
    coalesce(vq.Favorites,0) as Favorites,
    coalesce(vq.BountyAmountTotal,0) as BountyAmountTotal,
    coalesce(ca.CommentCount,0) as CommentCount,
    coalesce(ca.MaxCommentScore,0) as MaxCommentScore,
    coalesce(d.DuplicateLinks,0) as DuplicateLinks,
    coalesce(ce.CloseVotes,0) as CloseVotes,
    ce.LastCloseReasonId,
    ce.LastCloseOrReopenDate,
    coalesce(al.FirstAnswerLatencySeconds, null) as FirstAnswerLatencySeconds,
    coalesce(al.LastAnswerLatencySeconds, null) as LastAnswerLatencySeconds,
    coalesce(accl.AcceptedLatencySeconds, null) as AcceptedLatencySeconds,
    coalesce(qbd.BadgesPerSecond, 0.0) as OwnerBadgesPerSecond,
    qw.rn_by_popularity,
    qw.view_ntile,
    qw.cum_upvotes_by_time,
    qw.avg_net_votes_by_year,
    qf.QualityBucket,
    qf.IsPopularAnswered,
    qf.HasAnswersNoAccepted
  from q_windows qw
  left join votes vq on vq.PostId = qw.QuestionId
  left join comments_agg ca on ca.PostId = qw.QuestionId
  left join dupes d on d.QuestionId = qw.QuestionId
  left join close_events ce on ce.QuestionId = qw.QuestionId
  left join answer_latency al on al.QuestionId = qw.QuestionId
  left join accepted_latency accl on accl.QuestionId = qw.QuestionId
  left join q_badge_density qbd on qbd.QuestionId = qw.QuestionId
  left join quality_flags qf on qf.QuestionId = qw.QuestionId
),
tag_choice as (
  select
    tr.QuestionId,
    min(tr.TagName) filter (where tr.TagPopularityRank = 1) as TopTag,
    min(tr.TagName) filter (where tr.TagPopularityRank = 2) as SecondTag
  from tag_rank tr
  group by tr.QuestionId
),
final_rank as (
  select
    c.*,
    tc.TopTag,
    tc.SecondTag,
    greatest(1, c.QuestionScore + coalesce(c.UpVotes,0) - coalesce(c.DownVotes,0)) as NetScorePlus,
    case when c.AnswerCount > 0
      then coalesce(c.FirstAnswerLatencySeconds, 0)
      else null end as FirstLatencyIfAnswered,
    case
      when c.AcceptedLatencySeconds is null and c.AnswerCount > 0 then 1
      else 0
    end as HasNoAcceptedButAnswers,
    case
      when c.LastCloseReasonId in (101,102,103,104,105) then 'Current'
      when c.LastCloseReasonId in (1,2,3,4,7,10,20) then 'Legacy'
      else null
    end as CloseReasonEra,
    rank() over (
      order by
        coalesce(c.ViewCount,0) desc,
        coalesce(c.Favorites,0) desc,
        coalesce(c.BountyAmountTotal,0) desc,
        c.QuestionScore desc,
        c.CommentCount desc,
        c.DuplicateLinks asc,
        c.QuestionId
    ) as BenchmarkRank
  from calc c
  left join tag_choice tc on tc.QuestionId = c.QuestionId
),
-- Correlated subquery-driven enrichment
owner_enriched as (
  select
    fr.*,
    (
      select count(*) from Posts p_own
      where p_own.OwnerUserId = (select QuestionOwnerId from q_stats q2 where q2.QuestionId = fr.QuestionId)
        and p_own.PostTypeId = 1
    ) as OwnerQuestionCount,
    (
      select sum(coalesce(v2.UpVotes - v2.DownVotes,0))
      from Posts p2
      left join votes v2 on v2.PostId = p2.Id
      where p2.OwnerUserId = (select QuestionOwnerId from q_stats q3 where q3.QuestionId = fr.QuestionId)
    ) as OwnerNetVoteSum
  from final_rank fr
)
select
  oe.QuestionId,
  oe.Title,
  oe.TopTag,
  oe.SecondTag,
  oe.Tags,
  oe.QuestionScore,
  oe.ViewCount,
  oe.AnswerCount,
  oe.UpVotes,
  oe.DownVotes,
  oe.Favorites,
  oe.BountyAmountTotal,
  oe.CommentCount,
  oe.MaxCommentScore,
  oe.DuplicateLinks,
  oe.CloseVotes,
  oe.CloseReasonEra,
  oe.LastCloseOrReopenDate,
  oe.FirstAnswerLatencySeconds,
  oe.LastAnswerLatencySeconds,
  oe.AcceptedLatencySeconds,
  oe.OwnerBadgesPerSecond,
  oe.rn_by_popularity,
  oe.view_ntile,
  oe.cum_upvotes_by_time,
  oe.avg_net_votes_by_year,
  oe.QualityBucket,
  oe.IsPopularAnswered,
  oe.HasAnswersNoAccepted,
  oe.NetScorePlus,
  oe.FirstLatencyIfAnswered,
  oe.HasNoAcceptedButAnswers,
  oe.BenchmarkRank,
  oe.OwnerQuestionCount,
  oe.OwnerNetVoteSum
from owner_enriched oe
where
  -- complicated predicate mix
  (
    (oe.TopTag is not null and length(oe.TopTag) between 2 and 35)
    or (oe.Tags is null and oe.QuestionScore >= 0)
  )
  and coalesce(oe.ViewCount, 0) >= 0
  and not (oe.CloseReasonEra = 'Legacy' and coalesce(oe.DuplicateLinks,0) > 10)
  and (
    oe.AcceptedLatencySeconds is null
    or oe.AcceptedLatencySeconds >= 0
    or (oe.AnswerCount = 0 and oe.FirstAnswerLatencySeconds is null)
  )
  and (
    oe.BountyAmountTotal = 0
    or oe.BountyAmountTotal > 50
  )
  and (
    oe.QualityBucket in ('High','Medium')
    or (oe.QualityBucket = 'Low' and oe.ViewCount > 1000)
  )
order by
  oe.BenchmarkRank
limit 500;