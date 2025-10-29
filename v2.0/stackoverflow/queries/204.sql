-- {"query": "204.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2848}
with
q_posts as (
  select
    p.Id as QuestionId,
    p.CreationDate as QuestionCreation,
    p.OwnerUserId as QuestionOwnerId,
    p.Title,
    p.Tags,
    p.Score as QuestionScore,
    p.ViewCount,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    p.AcceptedAnswerId
  from Posts p
  where p.PostTypeId = 1
),
a_posts as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswerOwnerId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreation
  from Posts a
  where a.PostTypeId = 2
),
user_stats as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate as UserCreation,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    greatest(1, nullif(u.UpVotes + u.DownVotes, 0)) as NonZeroVoteActivity
  from Users u
),
badge_agg as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    count(*) as TotalBadges,
    min(b.Date) as FirstBadgeDate,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
comment_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(coalesce(c.Score, 0)) as CommentScoreSum,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
vote_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesCount,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesCount,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteCountLegacy,
    sum(case when v.VoteTypeId in (8, 9) then coalesce(v.BountyAmount, 0) else 0 end) as BountyTotal
  from Votes v
  group by v.PostId
),
dup_links as (
  select
    pl.PostId as DuplicateOfQuestionId,
    count(*) as DuplicateRefs,
    min(pl.CreationDate) as FirstDupLink,
    max(pl.CreationDate) as LastDupLink
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId
),
ph_close as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
    count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
    min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstCloseDate,
    max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastCloseDate,
    count(*) filter (where ph.PostHistoryTypeId in (35,36)) as Migrations
  from PostHistory ph
  group by ph.PostId
),
tag_explode as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as tag
  from q_posts q
  where q.Tags is not null and length(q.Tags) >= 2
),
tag_counts_per_q as (
  select
    QuestionId,
    count(*) as TagCount
  from tag_explode
  group by QuestionId
),
answer_rank as (
  select
    a.*,
    rank() over (partition by a.QuestionId order by a.AnswerScore desc nulls last, a.AnswerCreation asc nulls last, a.AnswerId asc) as RankByScore,
    count(*) over (partition by a.QuestionId) as AnswersForQ
  from a_posts a
),
best_nonaccepted as (
  select
    ar.QuestionId,
    ar.AnswerId as TopNonAcceptedAnswerId,
    ar.AnswerScore as TopNonAcceptedScore
  from answer_rank ar
  where ar.RankByScore = 1
),
accepted_answer as (
  select
    a.QuestionId,
    a.AnswerId as AcceptedAnswerId,
    a.AnswerScore as AcceptedAnswerScore,
    a.AnswerCreation as AcceptedAnswerCreation
  from a_posts a
  join q_posts q on q.AcceptedAnswerId = a.AnswerId
),
question_quality as (
  select
    q.QuestionId,
    q.Title,
    q.QuestionCreation,
    q.QuestionOwnerId,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    coalesce(tcpq.TagCount, 0) as TagCount,
    case
      when q.ViewCount is null then null
      when q.ViewCount = 0 then 0
      else round(1.0 * q.QuestionScore / nullif(q.ViewCount, 0), 6)
    end as ScorePerView,
    case
      when q.AnswerCount = 0 then null
      else round(1.0 * q.QuestionScore / q.AnswerCount, 6)
    end as ScorePerAnswer
  from q_posts q
  left join tag_counts_per_q tcpq on tcpq.QuestionId = q.QuestionId
),
owner_enriched as (
  select
    qq.*,
    us.DisplayName as OwnerName,
    us.Reputation as OwnerReputation,
    us.Location as OwnerLocation,
    ba.TotalBadges,
    coalesce(ba.GoldBadges,0) as GoldBadges,
    coalesce(ba.SilverBadges,0) as SilverBadges,
    coalesce(ba.BronzeBadges,0) as BronzeBadges
  from question_quality qq
  left join user_stats us on us.UserId = qq.QuestionOwnerId
  left join badge_agg ba on ba.UserId = qq.QuestionOwnerId
),
engagement as (
  select
    oe.QuestionId,
    oe.Title,
    oe.QuestionCreation,
    oe.OwnerName,
    oe.OwnerReputation,
    oe.OwnerLocation,
    oe.TotalBadges,
    oe.GoldBadges,
    oe.SilverBadges,
    oe.BronzeBadges,
    oe.QuestionScore,
    oe.ViewCount,
    oe.AnswerCount,
    oe.TagCount,
    oe.ScorePerView,
    oe.ScorePerAnswer,
    coalesce(va.UpVotesCount,0) as UpVotesCount,
    coalesce(va.DownVotesCount,0) as DownVotesCount,
    coalesce(va.FavoriteCountLegacy,0) as FavoriteCountLegacy,
    coalesce(va.BountyTotal,0) as BountyTotal,
    coalesce(ca.CommentCount,0) as CommentCount,
    coalesce(ca.CommentScoreSum,0) as CommentScoreSum,
    ca.LastCommentDate,
    coalesce(ph.CloseEvents,0) as CloseEvents,
    coalesce(ph.ReopenEvents,0) as ReopenEvents,
    ph.FirstCloseDate,
    ph.LastCloseDate,
    coalesce(dl.DuplicateRefs,0) as DuplicateRefs
  from owner_enriched oe
  left join vote_agg va on va.PostId = oe.QuestionId
  left join comment_agg ca on ca.PostId = oe.QuestionId
  left join ph_close ph on ph.PostId = oe.QuestionId
  left join dup_links dl on dl.DuplicateOfQuestionId = oe.QuestionId
),
ranked as (
  select
    e.*,
    row_number() over (order by
      (coalesce(e.UpVotesCount,0) - coalesce(e.DownVotesCount,0)) desc,
      e.FavoriteCountLegacy desc,
      e.CommentScoreSum desc,
      e.ViewCount desc,
      e.QuestionScore desc,
      e.BountyTotal desc,
      e.AnswerCount desc,
      e.DuplicateRefs asc nulls last,
      e.QuestionId asc
    ) as PopularityRank
  from engagement e
),
-- compute global median of net votes in a separate aggregation
global_net_median as (
  select
    percentile_cont(0.5) within group (order by netv) as GlobalNetVoteMedian
  from (
    select (coalesce(e.UpVotesCount,0) - coalesce(e.DownVotesCount,0)) as netv
    from engagement e
  ) t
),
accepted_vs_top as (
  select
    r.QuestionId,
    aa.AcceptedAnswerId,
    aa.AcceptedAnswerScore,
    bn.TopNonAcceptedAnswerId,
    bn.TopNonAcceptedScore,
    case
      when aa.AcceptedAnswerId is not null and bn.TopNonAcceptedAnswerId is not null
        then (coalesce(aa.AcceptedAnswerScore, -2147483648) >= coalesce(bn.TopNonAcceptedScore, -2147483648))
      when aa.AcceptedAnswerId is not null and bn.TopNonAcceptedAnswerId is null then true
      when aa.AcceptedAnswerId is null and bn.TopNonAcceptedAnswerId is not null then false
      else null
    end as AcceptedBeatsTopNonAccepted
  from ranked r
  left join accepted_answer aa on aa.QuestionId = r.QuestionId
  left join best_nonaccepted bn on bn.QuestionId = r.QuestionId
),
tag_popularity as (
  select
    te.tag,
    count(*) as TagUsageCount
  from tag_explode te
  group by te.tag
),
tagged_sample as (
  select
    r.QuestionId,
    r.Title,
    lower(trim(regexp_replace(coalesce(r.OwnerLocation,''), '\s+', ' ', 'g'))) as OwnerLocationNorm,
    string_agg(distinct te.tag, '|' order by te.tag) as TagList,
    sum(tp.TagUsageCount) as SumTagUsage
  from ranked r
  left join tag_explode te on te.QuestionId = r.QuestionId
  left join tag_popularity tp on tp.tag = te.tag
  group by r.QuestionId, r.Title, OwnerLocationNorm
),
final as (
  select
    r.PopularityRank,
    r.QuestionId,
    r.Title,
    r.OwnerName,
    r.OwnerReputation,
    r.OwnerLocation,
    ts.OwnerLocationNorm,
    ts.TagList,
    ts.SumTagUsage,
    r.QuestionCreation,
    r.QuestionScore,
    r.ViewCount,
    r.AnswerCount,
    r.TagCount,
    r.ScorePerView,
    r.ScorePerAnswer,
    r.UpVotesCount,
    r.DownVotesCount,
    (coalesce(r.UpVotesCount,0) - coalesce(r.DownVotesCount,0)) as NetVotes,
    r.FavoriteCountLegacy,
    r.BountyTotal,
    r.CommentCount,
    r.CommentScoreSum,
    r.LastCommentDate,
    r.CloseEvents,
    r.ReopenEvents,
    r.FirstCloseDate,
    r.LastCloseDate,
    r.DuplicateRefs,
    g.GlobalNetVoteMedian,
    av.AcceptedAnswerId,
    av.AcceptedAnswerScore,
    av.TopNonAcceptedAnswerId,
    av.TopNonAcceptedScore,
    av.AcceptedBeatsTopNonAccepted,
    case
      when r.TagCount = 0 or r.TagCount is null then 'untagged'
      when r.TagCount = 1 then 'single-tag'
      when r.TagCount between 2 and 3 then 'multi-tag-light'
      else 'multi-tag-heavy'
    end as TagDensityBucket,
    case
      when r.ViewCount is null then null
      when r.ViewCount = 0 then null
      else round(100.0 * (coalesce(r.UpVotesCount,0) - coalesce(r.DownVotesCount,0)) / r.ViewCount, 4)
    end as NetVotesPer100Views,
    case
      when r.AnswerCount > 0 then 'answered'
      else 'unanswered'
    end as AnswerStatus,
    case
      when r.CloseEvents > 0 then 'closed-or-reopened'
      else 'never-closed'
    end as ModerationStatus
  from ranked r
  cross join global_net_median g
  left join tagged_sample ts on ts.QuestionId = r.QuestionId
  left join accepted_vs_top av on av.QuestionId = r.QuestionId
)
select *
from final
where
  coalesce(NetVotes, -999999) >= coalesce(cast(GlobalNetVoteMedian as int), -999999)
  and (TagDensityBucket in ('single-tag','multi-tag-light') or SumTagUsage is null)
  and (OwnerReputation is null or OwnerReputation >= 1000)
  and (
    AcceptedBeatsTopNonAccepted is null
    or AcceptedBeatsTopNonAccepted = true
    or (AcceptedAnswerId is null and AnswerStatus = 'unanswered')
  )
  and (
    LastCloseDate is null
    or LastCloseDate > (QuestionCreation + interval '7 days')
  )
order by PopularityRank
limit 250;