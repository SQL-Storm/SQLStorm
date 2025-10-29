with recent_q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount
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
    a.CreationDate as AnswerDate,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc, a.Id asc) as rn_best_by_score
  from Posts a
  where a.PostTypeId = 2
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    u.CreationDate as UserCreated,
    coalesce(nullif(trim(u.Location), ''), 'Unknown') as LocationNorm
  from Users u
),
badges_agg as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as Golds,
    sum(case when b.Class = 2 then 1 else 0 end) as Silvers,
    sum(case when b.Class = 3 then 1 else 0 end) as Bronzes,
    min(b.Date) as FirstBadgeDate,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesOnPost,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesOnPost,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoritesOnPost,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyFlow
  from Votes v
  group by v.PostId
),
close_events as (
  select
    ph.PostId,
    min(case when ph.PostHistoryTypeId in (10,35) then ph.CreationDate end) as FirstCloseDate,
    max(case when ph.PostHistoryTypeId in (11) then ph.CreationDate end) as LastReopenDate,
    sum(case when ph.PostHistoryTypeId in (10,35) then 1 else 0 end) as CloseCount,
    sum(case when ph.PostHistoryTypeId in (11) then 1 else 0 end) as ReopenCount,
    -- extract a representative close reason if available
    max(case when ph.PostHistoryTypeId in (10,35) then cast(ph.Comment as integer) end) as AnyCloseReasonId
  from PostHistory ph
  group by ph.PostId
),
dup_links as (
  select
    pl.PostId as DuplicateOfId,
    pl.RelatedPostId as CanonicalId,
    pl.CreationDate as LinkDate,
    row_number() over (partition by pl.PostId order by pl.CreationDate asc) as rn_first_dup
  from PostLinks pl
  where pl.LinkTypeId = 3
),
tags_exploded as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag
  from recent_q q
  where q.Tags is not null
),
top_tag_per_question as (
  select
    te.QuestionId,
    min(te.tag) as AnyTag
  from tags_exploded te
  group by te.QuestionId
),
tag_stats as (
  select
    t.TagName,
    t.Count as GlobalTagCount,
    t.IsModeratorOnly,
    t.IsRequired
  from Tags t
),
question_engagement as (
  select
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    v.UpVotesOnPost,
    v.DownVotesOnPost,
    v.FavoritesOnPost,
    v.BountyFlow,
    coalesce(v.UpVotesOnPost,0) - coalesce(v.DownVotesOnPost,0) as NetVotes,
    case
      when q.ViewCount is null or q.ViewCount = 0 then null
      else (coalesce(v.UpVotesOnPost,0) * 1.0 / nullif(q.ViewCount,0)) end as UpvotePerViewRatio
  from recent_q q
  left join votes_agg v on v.PostId = q.QuestionId
),
best_answers as (
  select a.*
  from answers a
  where a.rn_best_by_score = 1
),
user_quality as (
  select
    us.UserId,
    us.Reputation,
    us.UpVotes,
    us.DownVotes,
    us.ProfileViews,
    us.UserCreated,
    us.LocationNorm,
    coalesce(b.Golds,0) as Golds,
    coalesce(b.Silvers,0) as Silvers,
    coalesce(b.Bronzes,0) as Bronzes,
    cast((coalesce(b.Golds,0)*10 + coalesce(b.Silvers,0)*3 + coalesce(b.Bronzes,0)) as numeric) as BadgeScore,
    case
      when us.Reputation = 0 then null
      else cast((coalesce(b.Golds,0)*10 + coalesce(b.Silvers,0)*3 + coalesce(b.Bronzes,0)) as numeric) / us.Reputation end as BadgePerRep
  from user_stats us
  left join badges_agg b on b.UserId = us.UserId
),
accepted_answer_latency as (
  select
    q.Id as QuestionId,
    q.CreationDate as QuestionDate,
    a.Id as AcceptedAnswerId,
    a.CreationDate as AcceptedDate,
    extract(epoch from (a.CreationDate - q.CreationDate)) / 3600.0 as HoursToAccept
  from Posts q
  join Posts a on a.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1
    and q.Id in (select QuestionId from recent_q)
),
ranked_questions as (
  select
    qe.QuestionId,
    qe.Title,
    qe.CreationDate,
    qe.Score,
    qe.ViewCount,
    qe.AnswerCount,
    qe.UpVotesOnPost,
    qe.DownVotesOnPost,
    qe.FavoritesOnPost,
    qe.BountyFlow,
    qe.NetVotes,
    qe.UpvotePerViewRatio,
    ca.HoursToAccept,
    dense_rank() over (order by coalesce(qe.NetVotes,0) desc, coalesce(qe.ViewCount,0) desc, coalesce(qe.FavoritesOnPost,0) desc, qe.CreationDate desc) as PopularityRank
  from question_engagement qe
  left join accepted_answer_latency ca on ca.QuestionId = qe.QuestionId
)
select
  rq.QuestionId,
  rq.Title,
  rq.CreationDate,
  rq.Score as QuestionScore,
  rq.ViewCount,
  rq.AnswerCount,
  rq.UpVotesOnPost,
  rq.DownVotesOnPost,
  rq.FavoritesOnPost,
  rq.BountyFlow,
  rq.NetVotes,
  round(coalesce(rq.UpvotePerViewRatio, 0), 6) as UpvotePerViewRatio,
  rq.HoursToAccept,
  rq.PopularityRank,
  ba.AnswerId as BestAnswerId,
  ba.AnswererId as BestAnswererId,
  ba.AnswerScore as BestAnswerScore,
  ba.AnswerDate as BestAnswerDate,
  oq.Reputation as OwnerReputation,
  oq.BadgeScore as OwnerBadgeScore,
  oq.BadgePerRep as OwnerBadgePerRep,
  oq.LocationNorm as OwnerLocation,
  aq.Reputation as AnswererReputation,
  aq.BadgeScore as AnswererBadgeScore,
  aq.BadgePerRep as AnswererBadgePerRep,
  aq.LocationNorm as AnswererLocation,
  ce.FirstCloseDate,
  ce.LastReopenDate,
  ce.CloseCount,
  ce.ReopenCount,
  crt.Name as AnyCloseReason,
  case when dl.DuplicateOfId is not null then 'Duplicate' else 'Unique' end as DupStatus,
  dl.CanonicalId as DuplicateCanonicalId,
  ttpq.AnyTag as RepresentativeTag,
  ts.GlobalTagCount as RepresentativeTagGlobalCount,
  ts.IsModeratorOnly,
  ts.IsRequired,
  upper(left(coalesce(rq.Title,''), 1)) || ':' || md5(coalesce(rq.Title,'')) as TitleSignature,
  case
    when coalesce(rq.NetVotes,0) >= 50 and coalesce(rq.ViewCount,0) >= 10000 then 'Hot'
    when coalesce(rq.NetVotes,0) <= -5 and coalesce(ce.CloseCount,0) > 0 then 'Controversial'
    when rq.HoursToAccept is null and rq.AnswerCount > 0 then 'Unaccepted'
    else 'Normal'
  end as EngagementBucket
from ranked_questions rq
left join best_answers ba on ba.QuestionId = rq.QuestionId
left join user_quality oq on oq.UserId = (select p.OwnerUserId from Posts p where p.Id = rq.QuestionId)
left join user_quality aq on aq.UserId = ba.AnswererId
left join close_events ce on ce.PostId = rq.QuestionId
left join CloseReasonTypes crt on crt.Id = ce.AnyCloseReasonId
left join dup_links dl on dl.DuplicateOfId = rq.QuestionId and dl.rn_first_dup = 1
left join top_tag_per_question ttpq on ttpq.QuestionId = rq.QuestionId
left join tag_stats ts on ts.TagName = ttpq.AnyTag
where
  (
    (rq.PopularityRank <= 200
      or rq.NetVotes >= all (
        select coalesce(v2.UpVotesOnPost,0) - coalesce(v2.DownVotesOnPost,0)
        from votes_agg v2
        where v2.PostId in (select QuestionId from recent_q)
      )
    )
    and (
      ce.FirstCloseDate is null
      or rq.CreationDate <= ce.FirstCloseDate + interval '7 days'
    )
  )
  and coalesce(oq.Reputation, 0) + coalesce(aq.Reputation, 0) >= 0
order by
  rq.PopularityRank,
  rq.QuestionId
limit 300;