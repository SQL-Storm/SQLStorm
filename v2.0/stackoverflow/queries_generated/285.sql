-- {"query": "285.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3990} 
with
q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AcceptedAnswerId,
    coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select date_trunc('year', min(CreationDate)) from Posts where PostTypeId = 1)
),
a as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswerOwnerId,
    a.CreationDate as AnswerCreationDate,
    a.Score as AnswerScore
  from Posts a
  where a.PostTypeId = 2
),
first_answer as (
  select
    a.QuestionId,
    min(a.AnswerCreationDate) as FirstAnswerDate
  from a
  group by a.QuestionId
),
answer_lags as (
  select
    a.QuestionId,
    a.AnswerId,
    a.AnswerOwnerId,
    a.AnswerCreationDate,
    a.AnswerScore,
    lag(a.AnswerCreationDate) over (partition by a.QuestionId order by a.AnswerCreationDate, a.AnswerId) as PrevAnswerDate,
    row_number() over (partition by a.QuestionId order by a.AnswerCreationDate, a.AnswerId) as AnswerOrdinal,
    dense_rank() over (partition by a.QuestionId order by a.AnswerScore desc nulls last, a.AnswerId) as ScoreRankWithinQ
  from a
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
    count(*) as TotalVotes
  from Votes v
  group by v.PostId
),
comments_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    max(c.CreationDate) as LastCommentDate,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments
  from Comments c
  group by c.PostId
),
edits as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditEvents,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as LastEditDate,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstCloseVoteDate,
    count(*) filter (where ph.PostHistoryTypeId in (11,13)) as UndeleteOrReopen
  from PostHistory ph
  group by ph.PostId
),
links as (
  select
    pl.PostId,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinks
  from PostLinks pl
  group by pl.PostId
),
dup_clusters as (
  select
    q.QuestionId,
    coalesce(sum(case when pl.LinkTypeId = 3 and pl.PostId = q.QuestionId then 1 else 0 end),0) +
    coalesce(sum(case when pl.LinkTypeId = 3 and pl.RelatedPostId = q.QuestionId then 1 else 0 end),0) as DuplicateDegree
  from q
  left join PostLinks pl
    on (pl.PostId = q.QuestionId or pl.RelatedPostId = q.QuestionId)
  group by q.QuestionId
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    min(b.Date) as FirstBadgeDate,
    count(*) as BadgeCount,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
tag_expansion as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from q
  where q.Tags is not null
),
tag_stats as (
  select
    t.tag as TagName,
    count(*) as QuestionTagCount
  from tag_expansion t
  group by t.tag
),
accepted_metrics as (
  select
    q.QuestionId,
    case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    case when q.AcceptedAnswerId is not null then
      extract(epoch from (
        (select a2.AnswerCreationDate from a a2 where a2.AnswerId = q.AcceptedAnswerId)
        - q.CreationDate
      ))::bigint
    else null end as SecondsToAccept
  from q
),
question_quality as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    coalesce(vq.UpVotes,0) as QUp,
    coalesce(vq.DownVotes,0) as QDown,
    coalesce(vq.Favorites,0) as QFav,
    coalesce(vq.BountyTotal,0) as QBounty,
    coalesce(cq.CommentCount,0) as QComments,
    coalesce(cq.PositiveComments,0) as QPositiveComments,
    coalesce(e.EditEvents,0) as QEdits,
    e.LastEditDate as QLastEdit,
    coalesce(e.CloseVotes,0) as QCloseVotes,
    e.FirstCloseVoteDate,
    coalesce(l.LinkedCount,0) as QLinked,
    coalesce(l.DuplicateLinks,0) as QDupLinks,
    dc.DuplicateDegree,
    am.HasAccepted,
    am.SecondsToAccept,
    case
      when q.ViewCount = 0 or q.ViewCount is null then null
      else round( (coalesce(vq.UpVotes,0)::numeric - coalesce(vq.DownVotes,0)::numeric) / nullif(q.ViewCount,0), 6)
    end as NetVotesPerView
  from q
  left join votes_agg vq on vq.PostId = q.QuestionId
  left join comments_agg cq on cq.PostId = q.QuestionId
  left join edits e on e.PostId = q.QuestionId
  left join links l on l.PostId = q.QuestionId
  left join dup_clusters dc on dc.QuestionId = q.QuestionId
  left join accepted_metrics am on am.QuestionId = q.QuestionId
),
answer_quality as (
  select
    al.QuestionId,
    al.AnswerId,
    al.AnswerOwnerId,
    al.AnswerCreationDate,
    al.AnswerScore,
    al.PrevAnswerDate,
    al.AnswerOrdinal,
    al.ScoreRankWithinQ,
    coalesce(va.UpVotes,0) as AUp,
    coalesce(va.DownVotes,0) as ADown,
    coalesce(va.BountyTotal,0) as ABountyOnAnswerPost,
    extract(epoch from (al.AnswerCreationDate - q.CreationDate))::bigint as SecondsFromQuestion,
    case when al.PrevAnswerDate is null then null
         else extract(epoch from (al.AnswerCreationDate - al.PrevAnswerDate))::bigint end as InterAnswerSeconds,
    coalesce(ca.CommentCount,0) as AComments
  from answer_lags al
  join q on q.QuestionId = al.QuestionId
  left join votes_agg va on va.PostId = al.AnswerId
  left join comments_agg ca on ca.PostId = al.AnswerId
),
ranked_answers as (
  select
    aq.*,
    row_number() over (partition by aq.QuestionId order by aq.AnswerScore desc nulls last, aq.AUp - aq.ADown desc, aq.AnswerCreationDate) as GlobalAnswerRank,
    percentile_cont(0.5) within group (order by aq.AnswerScore) over (partition by aq.QuestionId) as MedianAnswerScore
  from answer_quality aq
),
per_question_rollup as (
  select
    aq.QuestionId,
    count(*) as AnswerCnt,
    max(aq.AnswerScore) as MaxAnswerScore,
    avg(aq.AnswerScore::numeric) as AvgAnswerScore,
    sum(case when aq.AnswerScore > 0 then 1 else 0 end) as PositiveAnswerCount,
    min(aq.AnswerCreationDate) as FirstAnswerDate,
    max(aq.AnswerCreationDate) as LastAnswerDate,
    avg(aq.InterAnswerSeconds) filter (where aq.InterAnswerSeconds is not null) as AvgInterAnswerSeconds
  from answer_quality aq
  group by aq.QuestionId
),
question_user as (
  select
    qq.QuestionId,
    us.UserId as QUserId,
    us.Reputation as QReputation,
    us.BadgeCount as QBadgeCount,
    us.GoldBadges as QGold,
    us.SilverBadges as QSilver,
    us.BronzeBadges as QBronze
  from question_quality qq
  left join user_stats us on us.UserId = qq.OwnerUserId
),
answer_user as (
  select
    ra.QuestionId,
    ra.AnswerId,
    us.UserId as AUserId,
    us.Reputation as AReputation,
    us.BadgeCount as ABadgeCount
  from ranked_answers ra
  left join user_stats us on us.UserId = ra.AnswerOwnerId
),
top_answerers as (
  select distinct on (ra.QuestionId)
    ra.QuestionId,
    ra.AnswerId as TopAnswerId,
    ra.AnswerOwnerId as TopAnswerOwnerId,
    ra.AnswerScore as TopAnswerScore,
    ra.AUp - ra.ADown as TopAnswerNetVotes,
    ra.GlobalAnswerRank
  from ranked_answers ra
  where ra.AnswerScore is not null
  order by ra.QuestionId, ra.AnswerScore desc nulls last, (ra.AUp - ra.ADown) desc, ra.AnswerCreationDate
),
dup_or_linked as (
  select
    q.QuestionId,
    case
      when qq.QDupLinks > 0 then 'duplicate'
      when qq.QLinked > 0 then 'linked'
      else 'none'
    end as LinkClass
  from question_quality qq
  join q on q.QuestionId = qq.QuestionId
),
final_set as (
  select
    qq.QuestionId,
    qq.Title,
    qq.CreationDate,
    qq.Score,
    qq.ViewCount,
    qq.AnswerCount,
    qq.QUp, qq.QDown, qq.QFav, qq.QBounty,
    qq.QComments, qq.QPositiveComments,
    qq.QEdits, qq.QLastEdit,
    qq.QCloseVotes, qq.FirstCloseVoteDate,
    qq.QLinked, qq.QDupLinks, qq.DuplicateDegree,
    qq.HasAccepted, qq.SecondsToAccept,
    qq.NetVotesPerView,
    pqr.AnswerCnt,
    pqr.MaxAnswerScore,
    pqr.AvgAnswerScore,
    pqr.PositiveAnswerCount,
    pqr.FirstAnswerDate,
    pqr.LastAnswerDate,
    pqr.AvgInterAnswerSeconds,
    qa.QUserId, qa.QReputation, qa.QBadgeCount, qa.QGold, qa.QSilver, qa.QBronze,
    ta.TopAnswerId, ta.TopAnswerOwnerId, ta.TopAnswerScore, ta.TopAnswerNetVotes,
    dol.LinkClass
  from question_quality qq
  left join per_question_rollup pqr on pqr.QuestionId = qq.QuestionId
  left join question_user qa on qa.QuestionId = qq.QuestionId
  left join top_answerers ta on ta.QuestionId = qq.QuestionId
  left join dup_or_linked dol on dol.QuestionId = qq.QuestionId
),
-- Build a contrasting set via set operator for questions with no answers but with activity
no_answer_active as (
  select
    qq.QuestionId,
    qq.Title,
    qq.CreationDate,
    qq.Score,
    qq.ViewCount,
    qq.AnswerCount,
    qq.QUp, qq.QDown, qq.QFav, qq.QBounty,
    qq.QComments, qq.QPositiveComments,
    qq.QEdits, qq.QLastEdit,
    qq.QCloseVotes, qq.FirstCloseVoteDate,
    qq.QLinked, qq.QDupLinks, qq.DuplicateDegree,
    qq.HasAccepted, qq.SecondsToAccept,
    qq.NetVotesPerView,
    null::int as AnswerCnt,
    null::int as MaxAnswerScore,
    null::numeric as AvgAnswerScore,
    null::int as PositiveAnswerCount,
    null::timestamp as FirstAnswerDate,
    null::timestamp as LastAnswerDate,
    null::numeric as AvgInterAnswerSeconds,
    qa.QUserId, qa.QReputation, qa.QBadgeCount, qa.QGold, qa.QSilver, qa.QBronze,
    null::int as TopAnswerId, null::int as TopAnswerOwnerId, null::int as TopAnswerScore, null::int as TopAnswerNetVotes,
    case when coalesce(qq.QDupLinks,0) > 0 then 'duplicate'
         when coalesce(qq.QLinked,0) > 0 then 'linked'
         else 'none' end as LinkClass
  from question_quality qq
  left join per_question_rollup pqr on pqr.QuestionId = qq.QuestionId
  left join question_user qa on qa.QuestionId = qq.QuestionId
  where coalesce(pqr.AnswerCnt, 0) = 0
    and (coalesce(qq.QEdits,0) > 0 or coalesce(qq.QComments,0) > 0)
),
combined as (
  select * from final_set
  union all
  select * from no_answer_active
),
-- Apply correlated filters and computed predicates
scored as (
  select
    c.*,
    case when c.AnswerCnt is null then 0 else 1 end as HasAnswersFlag,
    coalesce(c.QUp - c.QDown, 0) as NetQVotes,
    case when c.LinkClass = 'duplicate' then 2 when c.LinkClass = 'linked' then 1 else 0 end as LinkWeight,
    case when c.SecondsToAccept is null then 0 else 1 end as AcceptedFlag,
    -- composite score blending engagement and quality
    (
      0.35 * coalesce(c.NetVotesPerView, 0) * greatest(c.ViewCount, 1) +
      0.20 * coalesce(c.QFav, 0) +
      0.15 * coalesce(c.AnswerCnt, 0) +
      0.10 * coalesce(c.MaxAnswerScore, 0) +
      0.10 * coalesce(c.TopAnswerNetVotes, 0) +
      0.05 * (coalesce(c.QComments,0) + coalesce(c.QEdits,0)) -
      0.05 * coalesce(c.QCloseVotes,0) -
      0.02 * coalesce(c.LinkWeight,0)
    )::numeric(20,4) as CompositeScore
  from combined c
  where not exists (
    select 1
    from PostHistory ph
    where ph.PostId = c.QuestionId
      and ph.PostHistoryTypeId in (12) -- deleted
  )
)
select
  s.QuestionId,
  s.Title,
  s.CreationDate,
  s.Score,
  s.ViewCount,
  s.AnswerCount,
  s.NetQVotes,
  s.HasAnswersFlag,
  s.AcceptedFlag,
  s.TopAnswerId,
  s.TopAnswerOwnerId,
  s.TopAnswerScore,
  s.TopAnswerNetVotes,
  s.QUserId,
  s.QReputation,
  s.QBadgeCount,
  s.QGold,
  s.QSilver,
  s.QBronze,
  s.QComments,
  s.QEdits,
  s.QCloseVotes,
  s.LinkClass,
  s.DuplicateDegree,
  s.SecondsToAccept,
  s.FirstAnswerDate,
  s.LastAnswerDate,
  s.AvgInterAnswerSeconds,
  s.CompositeScore,
  -- windowed benchmarks across partitions
  rank() over (order by s.CompositeScore desc nulls last) as GlobalRank,
  dense_rank() over (partition by case when s.HasAnswersFlag=1 then 'answered' else 'unanswered' end order by s.CompositeScore desc nulls last) as RankByAnswered,
  ntile(10) over (order by s.CompositeScore desc nulls last) as Decile,
  avg(s.CompositeScore) over (partition by s.LinkClass) as AvgScoreByLinkClass,
  count(*) over () as TotalRows
from scored s
where (
  s.ViewCount > 0
  and (
    s.HasAnswersFlag = 1
    or (s.HasAnswersFlag = 0 and s.QComments > 0)
  )
  and coalesce(s.QReputation, 0) >= (
    select percentile_disc(0.25) within group (order by coalesce(u.Reputation,0))
    from Users u
  )
  and (
    s.FirstAnswerDate is null
    or s.FirstAnswerDate >= s.CreationDate
  )
)
order by s.CompositeScore desc nulls last, s.ViewCount desc, s.QuestionId
limit 250;