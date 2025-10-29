with recent_q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    dense_rank() over (order by p.CreationDate desc, p.Id desc) as rec_rank
  from Posts p
  where p.PostTypeId = 1
),
top_recent as (
  select *
  from recent_q
  where rec_rank <= 500
),
answers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreationDate
  from Posts a
  where a.PostTypeId = 2
),
users_norm as (
  select
    u.Id as UserId,
    u.DisplayName,
    nullif(trim(coalesce(u.Location, '')), '') as Location,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate as UserCreationDate,
    u.LastAccessDate
  from Users u
),
badgeAgg as (
  select
    b.UserId,
    count(*) as BadgeCount,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
    min(v.CreationDate) as FirstVoteAt,
    max(v.CreationDate) as LastVoteAt
  from Votes v
  group by v.PostId
),
comments_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(coalesce(c.Score,0)) as CommentScoreSum,
    max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
link_dupes as (
  select
    pl.PostId,
    count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateLinks,
    count(case when pl.LinkTypeId = 1 then 1 end) as LinkedLinks,
    max(pl.CreationDate) as LastLinkAt
  from PostLinks pl
  group by pl.PostId
),
close_events as (
  select
    ph.PostId,
    min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstClosedAt,
    max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenedAt,
    count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseEvents,
    count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenEvents,
    max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonIdRaw
  from PostHistory ph
  group by ph.PostId
),
accepted as (
  select
    q.Id as QuestionId,
    q.AcceptedAnswerId,
    a.OwnerUserId as AcceptedOwnerUserId,
    a.Score as AcceptedAnswerScore,
    a.CreationDate as AcceptedAnswerDate
  from Posts q
  left join Posts a on a.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1
),
tag_expanded as (
  select
    t.QuestionId,
    unnest(string_to_array(substring(t.Tags, 2, length(t.Tags)-2), '><')) as tag
  from top_recent t
  where t.Tags is not null and length(t.Tags) > 2
),
tag_rank as (
  select
    QuestionId,
    tag,
    row_number() over (partition by QuestionId order by tag) as tag_ord
  from tag_expanded
),
primary_tag as (
  select tr.QuestionId, tr.tag as PrimaryTag
  from tag_rank tr
  where tr.tag_ord = 1
),
tag_meta as (
  select
    te.QuestionId,
    pt.PrimaryTag,
    tg.Count as PrimaryTagCount,
    tg.IsModeratorOnly,
    tg.IsRequired
  from primary_tag pt
  left join Tags tg on tg.TagName = pt.PrimaryTag
  right join top_recent te on te.QuestionId = pt.QuestionId
),
answer_stats as (
  select
    a.QuestionId,
    count(*) as AnswerCnt,
    max(a.AnswerScore) as MaxAnswerScore,
    avg(cast(a.AnswerScore as numeric)) as AvgAnswerScore,
    min(a.AnswerCreationDate) as FirstAnswerAt,
    max(a.AnswerCreationDate) as LastAnswerAt
  from answers a
  group by a.QuestionId
),
owner_activity as (
  select
    p.OwnerUserId as UserId,
    count(case when p.PostTypeId = 1 then 1 end) as QCount,
    count(case when p.PostTypeId = 2 then 1 end) as ACount,
    max(p.CreationDate) as LastPostAt
  from Posts p
  group by p.OwnerUserId
),
q_enriched as (
  select
    tr.QuestionId,
    tr.Title,
    tr.OwnerUserId,
    unullified.PrimaryTag,
    unullified.PrimaryTagCount,
    unullified.IsModeratorOnly,
    unullified.IsRequired,
    tr.CreationDate,
    tr.Score,
    tr.ViewCount,
    tr.Tags,
    tr.AnswerCount,
    vs.UpVotes as QUpVotes,
    vs.DownVotes as QDownVotes,
    vs.Favorites as QFavorites,
    vs.BountyTotal as QBountyTotal,
    vs.FirstVoteAt as QFirstVoteAt,
    vs.LastVoteAt as QLastVoteAt,
    ca.CommentCount as QCommentCount,
    ca.CommentScoreSum as QCommentScoreSum,
    ca.LastCommentAt as QLastCommentAt,
    le.DuplicateLinks,
    le.LinkedLinks,
    le.LastLinkAt,
    ce.FirstClosedAt,
    ce.LastReopenedAt,
    ce.CloseEvents,
    ce.ReopenEvents,
    ce.LastCloseReasonIdRaw,
    ac.AcceptedAnswerId,
    ac.AcceptedOwnerUserId,
    ac.AcceptedAnswerScore,
    ac.AcceptedAnswerDate,
    ast.AnswerCnt,
    ast.MaxAnswerScore,
    ast.AvgAnswerScore,
    ast.FirstAnswerAt,
    ast.LastAnswerAt
  from top_recent tr
  left join tag_meta unullified on unullified.QuestionId = tr.QuestionId
  left join votes_agg vs on vs.PostId = tr.QuestionId
  left join comments_agg ca on ca.PostId = tr.QuestionId
  left join link_dupes le on le.PostId = tr.QuestionId
  left join close_events ce on ce.PostId = tr.QuestionId
  left join accepted ac on ac.QuestionId = tr.QuestionId
  left join answer_stats ast on ast.QuestionId = tr.QuestionId
),
owner_enriched as (
  select
    q.QuestionId,
    u.DisplayName as OwnerDisplayName,
    u.Location as OwnerLocation,
    u.Reputation as OwnerReputation,
    u.UpVotes as OwnerUpVotes,
    u.DownVotes as OwnerDownVotes,
    u.UserCreationDate as OwnerUserCreationDate,
    u.LastAccessDate as OwnerLastAccessDate,
    ba.BadgeCount as OwnerBadgeCount,
    ba.GoldCount as OwnerGold,
    ba.SilverCount as OwnerSilver,
    ba.BronzeCount as OwnerBronze,
    ba.LastBadgeDate as OwnerLastBadgeDate,
    oa.QCount as OwnerQCount,
    oa.ACount as OwnerACount,
    oa.LastPostAt as OwnerLastPostAt
  from q_enriched q
  left join users_norm u on u.UserId = q.OwnerUserId
  left join badgeAgg ba on ba.UserId = q.OwnerUserId
  left join owner_activity oa on oa.UserId = q.OwnerUserId
),
accepted_owner_enriched as (
  select
    q.QuestionId,
    u.DisplayName as AccOwnerDisplayName,
    u.Location as AccOwnerLocation,
    u.Reputation as AccOwnerReputation,
    ba.BadgeCount as AccOwnerBadgeCount,
    ba.GoldCount as AccOwnerGold,
    ba.SilverCount as AccOwnerSilver,
    ba.BronzeCount as AccOwnerBronze
  from q_enriched q
  left join users_norm u on u.UserId = q.AcceptedOwnerUserId
  left join badgeAgg ba on ba.UserId = q.AcceptedOwnerUserId
),
quality_flags as (
  select
    q.QuestionId,
    case when coalesce(q.Score,0) >= 5 and coalesce(q.QUpVotes,0) - coalesce(q.QDownVotes,0) >= 5 then 1 else 0 end as IsWellReceived,
    case when coalesce(q.ViewCount,0) >= 1000 then 1 else 0 end as IsPopular,
    case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    case when q.FirstClosedAt is not null and (q.LastReopenedAt is null or q.FirstClosedAt > q.LastReopenedAt) then 1 else 0 end as IsCurrentlyClosed,
    case when q.AnswerCnt is null or q.AnswerCnt = 0 then 1 else 0 end as IsUnanswered,
    case when q.AvgAnswerScore is not null and q.AvgAnswerScore > 1 then 1 else 0 end as HasGoodAnswers,
    case when q.PrimaryTagCount is not null and q.PrimaryTagCount > 10000 then 1 else 0 end as IsMainstreamTag
  from q_enriched q
),
ranked as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.PrimaryTag,
    q.PrimaryTagCount,
    q.IsModeratorOnly,
    q.IsRequired,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.Tags,
    q.AnswerCount,
    q.QUpVotes,
    q.QDownVotes,
    q.QFavorites,
    q.QBountyTotal,
    q.QFirstVoteAt,
    q.QLastVoteAt,
    q.QCommentCount,
    q.QCommentScoreSum,
    q.QLastCommentAt,
    q.DuplicateLinks,
    q.LinkedLinks,
    q.LastLinkAt,
    q.FirstClosedAt,
    q.LastReopenedAt,
    q.CloseEvents,
    q.ReopenEvents,
    q.LastCloseReasonIdRaw,
    q.AcceptedAnswerId,
    q.AcceptedOwnerUserId,
    q.AcceptedAnswerScore,
    q.AcceptedAnswerDate,
    q.AnswerCnt,
    q.MaxAnswerScore,
    q.AvgAnswerScore,
    q.FirstAnswerAt,
    q.LastAnswerAt,
    oe.OwnerDisplayName,
    oe.OwnerLocation,
    oe.OwnerReputation,
    oe.OwnerUpVotes,
    oe.OwnerDownVotes,
    oe.OwnerUserCreationDate,
    oe.OwnerLastAccessDate,
    oe.OwnerBadgeCount,
    oe.OwnerGold,
    oe.OwnerSilver,
    oe.OwnerBronze,
    oe.OwnerLastBadgeDate,
    oe.OwnerQCount,
    oe.OwnerACount,
    oe.OwnerLastPostAt,
    aoe.AccOwnerDisplayName,
    aoe.AccOwnerLocation,
    aoe.AccOwnerReputation,
    aoe.AccOwnerBadgeCount,
    aoe.AccOwnerGold,
    aoe.AccOwnerSilver,
    aoe.AccOwnerBronze,
    qf.IsWellReceived,
    qf.IsPopular,
    qf.HasAccepted,
    qf.IsCurrentlyClosed,
    qf.IsUnanswered,
    qf.HasGoodAnswers,
    qf.IsMainstreamTag,
    dense_rank() over (
      order by
        coalesce(q.Score,0) desc,
        coalesce(q.ViewCount,0) desc,
        coalesce(q.QFavorites,0) desc,
        coalesce(q.AvgAnswerScore, -1) desc,
        q.CreationDate desc
    ) as GlobalRank,
    row_number() over (
      partition by coalesce(oe.OwnerDisplayName, 'Unknown')
      order by coalesce(q.Score,0) desc, q.CreationDate desc
    ) as OwnerLocalRank
  from q_enriched q
  left join owner_enriched oe on oe.QuestionId = q.QuestionId
  left join accepted_owner_enriched aoe on aoe.QuestionId = q.QuestionId
  left join quality_flags qf on qf.QuestionId = q.QuestionId
),
stringified as (
  select
    r.QuestionId,
    r.Title,
    r.OwnerUserId,
    r.PrimaryTag,
    r.PrimaryTagCount,
    r.IsModeratorOnly,
    r.IsRequired,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.AnswerCount,
    r.QUpVotes,
    r.QDownVotes,
    r.QFavorites,
    r.QBountyTotal,
    r.QFirstVoteAt,
    r.QLastVoteAt,
    r.QCommentCount,
    r.QCommentScoreSum,
    r.QLastCommentAt,
    r.DuplicateLinks,
    r.LinkedLinks,
    r.LastLinkAt,
    r.FirstClosedAt,
    r.LastReopenedAt,
    r.CloseEvents,
    r.ReopenEvents,
    r.LastCloseReasonIdRaw,
    r.AcceptedAnswerId,
    r.AcceptedOwnerUserId,
    r.AcceptedAnswerScore,
    r.AcceptedAnswerDate,
    r.AnswerCnt,
    r.MaxAnswerScore,
    r.AvgAnswerScore,
    r.FirstAnswerAt,
    r.LastAnswerAt,
    r.OwnerDisplayName,
    r.OwnerLocation,
    r.OwnerReputation,
    r.OwnerUpVotes,
    r.OwnerDownVotes,
    r.OwnerUserCreationDate,
    r.OwnerLastAccessDate,
    r.OwnerBadgeCount,
    r.OwnerGold,
    r.OwnerSilver,
    r.OwnerBronze,
    r.OwnerLastBadgeDate,
    r.OwnerQCount,
    r.OwnerACount,
    r.OwnerLastPostAt,
    r.AccOwnerDisplayName,
    r.AccOwnerLocation,
    r.AccOwnerReputation,
    r.AccOwnerBadgeCount,
    r.AccOwnerGold,
    r.AccOwnerSilver,
    r.AccOwnerBronze,
    r.IsWellReceived,
    r.IsPopular,
    r.HasAccepted,
    r.IsCurrentlyClosed,
    r.IsUnanswered,
    r.HasGoodAnswers,
    r.IsMainstreamTag,
    r.GlobalRank,
    r.OwnerLocalRank,
    coalesce('[' || array_to_string(string_to_array(substring(r.Tags, 2, greatest(length(r.Tags)-2,0)), '><'), ', ') || ']', '[]') as TagsPretty,
    trim(both from regexp_replace(coalesce(r.Title, ''), '\s+', ' ', 'g')) as TitleSquished,
    case
      when r.PrimaryTag is null then 'untagged'
      when r.IsModeratorOnly = true then coalesce(r.PrimaryTag,'') || ' (mod-only)'
      when r.IsRequired = true then coalesce(r.PrimaryTag,'') || ' (required)'
      else r.PrimaryTag
    end as PrimaryTagDecorated,
    case
      when r.LastCloseReasonIdRaw ~ '^\d+$' then cast(r.LastCloseReasonIdRaw as integer)
      else null
    end as LastCloseReasonId
  from ranked r
),
score_bins as (
  select
    s.*,
    -- emulate width_bucket using a portable expression
    floor(
      greatest(
        least(
          (coalesce(s.Score,0) - (-5)) / nullif((50 - (-5)),0) * 11 + 1,
          11
        ),
        1
      )
    )::integer as ScoreBucket,
    floor(
      greatest(
        least(
          (coalesce(s.ViewCount,0) - 0) / nullif((100000 - 0),0) * 10 + 1,
          10
        ),
        1
      )
    )::integer as ViewBucket
  from stringified s
),
final as (
  select
    sb.*,
    count(*) over () as SampleSize,
    sum(case when IsWellReceived = 1 then 1 else 0 end) over () as TotalWellReceived,
    avg(coalesce(AvgAnswerScore,0)) over () as GlobalAvgAnswerScore,
    sum(case when HasAccepted = 1 then 1 else 0 end) over (partition by PrimaryTagDecorated) as TagAcceptedCount,
    rank() over (partition by PrimaryTagDecorated order by coalesce(Score,0) desc, coalesce(ViewCount,0) desc) as RankWithinTag,
    lag(Score) over (order by GlobalRank) as PrevScoreByGlobal,
    lead(Score) over (order by GlobalRank) as NextScoreByGlobal
  from score_bins sb
)
select
  f.QuestionId,
  f.GlobalRank,
  f.OwnerLocalRank,
  f.TitleSquished as Title,
  f.TagsPretty,
  f.PrimaryTagDecorated as PrimaryTag,
  f.PrimaryTagCount,
  f.Score,
  f.ViewCount,
  f.QUpVotes,
  f.QDownVotes,
  (coalesce(f.QUpVotes,0) - coalesce(f.QDownVotes,0)) as NetVotes,
  f.QFavorites,
  f.QBountyTotal,
  f.QFirstVoteAt,
  f.QLastVoteAt,
  f.QCommentCount,
  f.QCommentScoreSum,
  f.QLastCommentAt,
  f.DuplicateLinks,
  f.LinkedLinks,
  f.LastLinkAt,
  f.FirstClosedAt,
  f.LastReopenedAt,
  f.CloseEvents,
  f.ReopenEvents,
  f.LastCloseReasonId,
  f.AnswerCount as DeclaredAnswerCount,
  f.AnswerCnt as ComputedAnswerCount,
  f.MaxAnswerScore,
  f.AvgAnswerScore,
  f.FirstAnswerAt,
  f.LastAnswerAt,
  f.AcceptedAnswerId,
  f.AcceptedAnswerScore,
  f.AcceptedAnswerDate,
  f.OwnerDisplayName,
  coalesce(f.OwnerLocation, 'Unknown') as OwnerLocation,
  f.OwnerReputation,
  f.OwnerUpVotes,
  f.OwnerDownVotes,
  f.OwnerBadgeCount,
  f.OwnerGold,
  f.OwnerSilver,
  f.OwnerBronze,
  f.OwnerUserCreationDate,
  f.OwnerLastAccessDate,
  f.OwnerQCount,
  f.OwnerACount,
  f.OwnerLastPostAt,
  f.AccOwnerDisplayName,
  f.AccOwnerLocation,
  f.AccOwnerReputation,
  f.AccOwnerBadgeCount,
  f.AccOwnerGold,
  f.AccOwnerSilver,
  f.AccOwnerBronze,
  f.IsWellReceived,
  f.IsPopular,
  f.HasAccepted,
  f.IsCurrentlyClosed,
  f.IsUnanswered,
  f.HasGoodAnswers,
  f.IsMainstreamTag,
  f.ScoreBucket,
  f.ViewBucket,
  f.SampleSize,
  f.TotalWellReceived,
  f.GlobalAvgAnswerScore,
  f.TagAcceptedCount,
  f.RankWithinTag,
  f.PrevScoreByGlobal,
  f.NextScoreByGlobal
from final f
where
  (
    coalesce(f.IsCurrentlyClosed,0) = 0
    or coalesce(f.ReopenEvents,0) > 0
  )
  and (
    f.OwnerReputation is null
    or f.OwnerReputation >= 50
  )
  and (
    f.PrimaryTagCount is null
    or f.PrimaryTagCount > 50
  )
order by
  f.GlobalRank,
  f.QuestionId
limit 200;