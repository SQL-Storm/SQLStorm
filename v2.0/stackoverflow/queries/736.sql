with params as (
  select
    interval '365 days' as recent_window,
    interval '90 days' as hot_window,
    50 as min_rep,
    5 as min_answers
),
recent_questions as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.Title,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    case when p.ClosedDate is not null then 1 else 0 end as IsClosed
  from Posts p
  join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
  cross join params pr
  where p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - pr.recent_window
),
answers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswerOwnerId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreationDate
  from Posts a
  join PostTypes pt on pt.Id = a.PostTypeId and pt.Name = 'Answer'
),
answerers as (
  select
    r.QuestionId,
    count(*) filter (where u.Reputation >= (select min_rep from params)) as QualifiedAnswerers,
    avg(cast(u.Reputation as numeric)) as AvgAnswererRep,
    max(u.Reputation) as MaxAnswererRep
  from recent_questions r
  left join answers a on a.QuestionId = r.QuestionId
  left join Users u on u.Id = a.AnswerOwnerId
  group by r.QuestionId
),
question_votes as (
  select
    v.PostId as QuestionId,
    sum(case when vt.Name = 'UpMod' then 1 when vt.Name = 'DownMod' then -1 else 0 end) as NetVotes,
    sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
    sum(case when vt.Name = 'BountyStart' then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
    sum(case when vt.Name = 'BountyClose' then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
    count(*) as TotalVotes
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
hot_activity as (
  select
    r.QuestionId,
    count(distinct c.Id) filter (where c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - (select hot_window from params)) as RecentComments,
    count(distinct a.AnswerId) filter (where a.AnswerCreationDate >= cast('2024-10-01 12:34:56' as timestamp) - (select hot_window from params)) as RecentAnswers
  from recent_questions r
  left join Comments c on c.PostId = r.QuestionId
  left join answers a on a.QuestionId = r.QuestionId
  group by r.QuestionId
),
tag_split as (
  select
    r.QuestionId,
    unnest(string_to_array(substring(r.Tags, 2, greatest(length(r.Tags)-2,0)), '><')) as tag
  from recent_questions r
  where r.Tags is not null
),
tag_stats as (
  select
    ts.QuestionId,
    count(*) as TagCount,
    string_agg(ts.tag, ',' order by ts.tag) as TagList,
    sum(t.Count) as TagPopularity,
    max(case when t.IsModeratorOnly then 1 else 0 end) as HasModOnlyTag,
    max(case when t.IsRequired then 1 else 0 end) as HasRequiredTag
  from tag_split ts
  left join Tags t on lower(t.TagName) = lower(ts.tag)
  group by ts.QuestionId
),
edits as (
  select
    ph.PostId as QuestionId,
    count(*) filter (where pht.Name in ('Edit Title','Edit Body','Edit Tags')) as EditCount,
    max(ph.CreationDate) filter (where pht.Name in ('Edit Title','Edit Body','Edit Tags')) as LastEditDate,
    count(*) filter (where pht.Name like 'Post %' or pht.Name in ('Community Owned','Question Protected','Question Unprotected')) as ModEvents
  from PostHistory ph
  join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
  group by ph.PostId
),
closures as (
  select
    ph.PostId as QuestionId,
    min(ph.CreationDate) filter (where pht.Name = 'Post Closed') as FirstClosedDate,
    max(ph.CreationDate) filter (where pht.Name = 'Post Reopened') as LastReopenedDate,
    count(*) filter (where pht.Name = 'Post Closed') as CloseCount,
    count(*) filter (where pht.Name = 'Post Reopened') as ReopenCount,
    max(case
      when pht.Name = 'Post Closed' and ph.Comment ~ '^[0-9]+$'
      then cast(ph.Comment as int)
      else null
    end) as LastCloseReasonId
  from PostHistory ph
  join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
  group by ph.PostId
),
dup_links as (
  select
    pl.PostId as DuplicateOf,
    count(*) filter (where lt.Name = 'Duplicate') as DuplicateLinks,
    count(*) filter (where lt.Name = 'Linked') as LinkedRefs
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId
),
user_agg as (
  select
    u.Id as UserId,
    count(*) filter (where pt.Name = 'Question') as TotalQuestions,
    count(*) filter (where pt.Name = 'Answer') as TotalAnswers,
    sum(coalesce(p.Score,0)) as TotalPostScore,
    max(u.Reputation) as Reputation,
    min(u.CreationDate) as UserSince
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join PostTypes pt on pt.Id = p.PostTypeId
  group by u.Id
),
accepted as (
  select
    q.Id as QuestionId,
    case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    aa.Score as AcceptedScore,
    aa.OwnerUserId as AcceptedOwnerId
  from Posts q
  left join Posts aa on aa.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1
),
question_rank as (
  select
    r.QuestionId,
    r.Title,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    coalesce(tv.NetVotes, 0) as NetVotes,
    coalesce(tv.Favorites, 0) as Favorites,
    coalesce(tv.BountyStarted - tv.BountyAwarded, 0) as BountyDelta,
    coalesce(ha.RecentComments, 0) as RecentComments,
    coalesce(ha.RecentAnswers, 0) as RecentAnswers,
    coalesce(ts.TagCount, 0) as TagCount,
    coalesce(ts.TagPopularity, 0) as TagPopularity,
    coalesce(ts.TagList, '') as TagList,
    coalesce(ed.EditCount, 0) as EditCount,
    ed.LastEditDate,
    coalesce(ed.ModEvents, 0) as ModEvents,
    cl.FirstClosedDate,
    cl.LastReopenedDate,
    coalesce(cl.CloseCount, 0) as CloseCount,
    coalesce(cl.ReopenCount, 0) as ReopenCount,
    cl.LastCloseReasonId,
    coalesce(dl.DuplicateLinks, 0) as DuplicateLinks,
    coalesce(dl.LinkedRefs, 0) as LinkedRefs,
    coalesce(ans.QualifiedAnswerers, 0) as QualifiedAnswerers,
    ans.AvgAnswererRep,
    ans.MaxAnswererRep,
    r.AnswerCount,
    r.IsClosed,
    acc.HasAccepted,
    acc.AcceptedScore,
    ua.Reputation as OwnerReputation,
    ua.TotalQuestions as OwnerTotalQuestions,
    ua.TotalAnswers as OwnerTotalAnswers,
    case
      when r.ViewCount > 0 then (cast(r.Score as numeric) / r.ViewCount) else null
    end as ScorePerView,
    extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - r.CreationDate))/3600.0 as AgeHours,
    case
      when r.AnswerCount >= (select min_answers from params) then 1 else 0
    end as IsHighlyAnswered
  from recent_questions r
  left join question_votes tv on tv.QuestionId = r.QuestionId
  left join hot_activity ha on ha.QuestionId = r.QuestionId
  left join tag_stats ts on ts.QuestionId = r.QuestionId
  left join edits ed on ed.QuestionId = r.QuestionId
  left join closures cl on cl.QuestionId = r.QuestionId
  left join dup_links dl on dl.DuplicateOf = r.QuestionId
  left join answerers ans on ans.QuestionId = r.QuestionId
  left join accepted acc on acc.QuestionId = r.QuestionId
  left join user_agg ua on ua.UserId = r.OwnerUserId
),
score_calc as (
  select
    qr.*,
    (
      coalesce(qr.NetVotes,0)*1.5
      + coalesce(qr.Favorites,0)*2
      + coalesce(qr.RecentAnswers,0)*3
      + coalesce(qr.RecentComments,0)*0.5
      + coalesce(qr.TagPopularity,0)*0.001
      + coalesce(qr.EditCount,0)*(-0.3)
      + coalesce(qr.ModEvents,0)*(-0.5)
      + coalesce(qr.DuplicateLinks,0)*(-2)
      + case when qr.IsClosed = 1 then -5 else 0 end
      + case when qr.HasAccepted = 1 then 4 else 0 end
      + least(coalesce(qr.ScorePerView,0)*100, 20)
      + least(coalesce(qr.OwnerReputation,0)/100.0, 20)
      - least(coalesce(qr.AgeHours,0)/24.0, 10)
      + case when qr.IsHighlyAnswered = 1 then 3 else 0 end
    ) as HotnessScore
  from question_rank qr
),
dense as (
  select
    sc.*,
    row_number() over (order by sc.HotnessScore desc, sc.CreationDate desc) as rn,
    dense_rank() over (order by coalesce(sc.TagPopularity,0) desc) as TagPopRank,
    percent_rank() over (order by coalesce(sc.OwnerReputation,0)) as OwnerRepPercentile,
    ntile(4) over (order by coalesce(sc.ViewCount,0) desc) as ViewQuartile,
    sum(case when sc.HasAccepted = 1 then 1 else 0 end) over () as TotalAcceptedInWindow,
    count(*) over () as TotalQuestionsInWindow
  from score_calc sc
),
with_null_logic as (
  select
    d.*,
    coalesce(nullif(d.TagList,''), '(no-tags)') as SafeTagList,
    case when d.LastEditDate is null then d.CreationDate else d.LastEditDate end as LastTouched,
    case
      when d.FirstClosedDate is not null and d.LastReopenedDate is null then 'Closed'
      when d.FirstClosedDate is not null and d.LastReopenedDate is not null and d.LastReopenedDate > d.FirstClosedDate then 'Reopened'
      else 'Open'
    end as ClosureState
  from dense d
),
owner_quality as (
  select
    w.QuestionId,
    case
      when w.OwnerReputation >= 20000 then 'Legend'
      when w.OwnerReputation >= 10000 then 'Expert'
      when w.OwnerReputation >= 2000 then 'Seasoned'
      when w.OwnerReputation is null then 'Unknown'
      else 'Regular'
    end as OwnerTier
  from with_null_logic w
),
thresholds as (
  select
    percentile_disc(0.9) within group (order by HotnessScore) as p90,
    percentile_disc(0.75) within group (order by HotnessScore) as p75,
    percentile_disc(0.5) within group (order by HotnessScore) as p50
  from score_calc
),
final as (
  select
    w.QuestionId,
    w.Title,
    w.CreationDate,
    w.ViewCount,
    w.Score,
    w.NetVotes,
    w.Favorites,
    w.AnswerCount,
    w.QualifiedAnswerers,
    w.AvgAnswererRep,
    w.MaxAnswererRep,
    w.TagCount,
    w.SafeTagList as Tags,
    w.TagPopularity,
    w.EditCount,
    w.ModEvents,
    w.CloseCount,
    w.ReopenCount,
    w.ClosureState,
    w.DuplicateLinks,
    w.LinkedRefs,
    w.OwnerUserId,
    w.OwnerReputation,
    w.OwnerTotalQuestions,
    w.OwnerTotalAnswers,
    w.ScorePerView,
    w.AgeHours,
    w.HasAccepted,
    w.AcceptedScore,
    w.BountyDelta,
    w.HotnessScore,
    w.TagPopRank,
    w.OwnerRepPercentile,
    w.ViewQuartile,
    w.rn as RowNum,
    oq.OwnerTier,
    t.p90,
    t.p75,
    t.p50,
    case
      when w.HotnessScore >= t.p90 then 'S-Tier'
      when w.HotnessScore >= t.p75 then 'A-Tier'
      when w.HotnessScore >= t.p50 then 'B-Tier'
      else 'C-Tier'
    end as HotTier
  from with_null_logic w
  left join owner_quality oq on oq.QuestionId = w.QuestionId
  cross join thresholds t
)
select *
from final
where
  (
    (HotTier in ('S-Tier','A-Tier') and ClosureState <> 'Closed')
    or (HasAccepted = 1 and ScorePerView is not null and ScorePerView > 0)
    or (DuplicateLinks = 0 and coalesce(TagCount,0) between 2 and 5)
  )
  and coalesce(OwnerReputation, 0) >= (select min_rep from params)
  and not (Tags ilike '%regex%' and OwnerRepPercentile < 0.2)
  and coalesce(TagPopularity, 0) >= 0
order by HotnessScore desc, CreationDate desc
limit 200;