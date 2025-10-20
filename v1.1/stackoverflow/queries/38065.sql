with recent_q as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.Title,
    coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '90 days' from Posts where PostTypeId = 1)
),
answers as (
  select a.ParentId as QuestionId,
         a.Id as AnswerId,
         a.OwnerUserId as AnswerOwnerId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreationDate
  from Posts a
  where a.PostTypeId = 2
),
first_answer as (
  select
    a.QuestionId,
    min(a.AnswerCreationDate) as FirstAnswerDate
  from answers a
  group by a.QuestionId
),
accepted as (
  select
    q.Id as QuestionId,
    q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1
    and q.AcceptedAnswerId is not null
),
q_votes as (
  select
    v.PostId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    count(*) filter (where v.VoteTypeId in (8,9)) as BountyVotes,
    sum(coalesce(v.BountyAmount,0)) as TotalBounty
  from Votes v
  join Posts p on p.Id = v.PostId and p.PostTypeId = 1
  group by v.PostId
),
a_votes as (
  select
    a.ParentId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetAnswerVotes,
    count(*) filter (where v.VoteTypeId = 1) as AcceptedByOriginatorFlags
  from Votes v
  join Posts a on a.Id = v.PostId and a.PostTypeId = 2
  group by a.ParentId
),
comment_counts as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments
  from Comments c
  group by c.PostId
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    date_part('day', cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate) as UserAgeDays
  from Users u
),
tag_explode as (
  select
    rq.QuestionId,
    unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) as tag
  from recent_q rq
  where rq.Tags is not null and rq.Tags like '<%>'
),
tag_ranks as (
  select
    te.tag,
    count(*) as TagQCount,
    sum(rq.ViewCount) as TagViews,
    avg(rq.Score) as AvgTagScore
  from tag_explode te
  join recent_q rq on rq.QuestionId = te.QuestionId
  group by te.tag
  having count(*) >= 5
),
duplicate_links as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateRefs,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedRefs
  from PostLinks pl
  group by pl.PostId
),
edits as (
  select
    ph.PostId as QuestionId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditDate,
    count(*) filter (where ph.PostHistoryTypeId = 24) as SuggestedEditsApplied,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesInPH
  from PostHistory ph
  group by ph.PostId
),
badges_by_asker as (
  select
    b.UserId,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges
  from Badges b
  group by b.UserId
),
answerer_diversity as (
  select
    a.QuestionId,
    count(distinct a.AnswerOwnerId) as DistinctAnswerers
  from answers a
  group by a.QuestionId
),
quality_score as (
  select
    rq.QuestionId,
    (coalesce(qv.NetVotes,0) * 2
     + coalesce(av.NetAnswerVotes,0)
     + greatest(0, coalesce(cc.CommentCount,0) - coalesce(cc.PositiveComments,0)) * -0.5
     + coalesce(qv.Favorites,0) * 1.5
     + coalesce(qv.TotalBounty,0) / 50.0
     + coalesce(ed.EditCount,0) * 0.2
     + coalesce(dl.LinkedRefs,0) * 0.1
     - coalesce(dl.DuplicateRefs,0) * 2
     + case when rq.AnswerCount > 0 then 3 else 0 end
     + least(coalesce(ad.DistinctAnswerers,0), 10) * 0.3
    ) as ComputedQuality
  from recent_q rq
  left join q_votes qv on qv.QuestionId = rq.QuestionId
  left join a_votes av on av.QuestionId = rq.QuestionId
  left join comment_counts cc on cc.PostId = rq.QuestionId
  left join edits ed on ed.QuestionId = rq.QuestionId
  left join duplicate_links dl on dl.QuestionId = rq.QuestionId
  left join answerer_diversity ad on ad.QuestionId = rq.QuestionId
),
accepted_latency as (
  select
    rq.QuestionId,
    extract(epoch from (a.FirstAnswerDate - rq.CreationDate))/3600.0 as HoursToFirstAnswer,
    extract(epoch from (accAns.CreationDate - rq.CreationDate))/3600.0 as HoursToAcceptedAnswer
  from recent_q rq
  left join first_answer a on a.QuestionId = rq.QuestionId
  left join accepted ac on ac.QuestionId = rq.QuestionId
  left join Posts accAns on accAns.Id = ac.AcceptedAnswerId
),
top_tags as (
  select tag
  from tag_ranks
  order by TagQCount desc, TagViews desc
  limit 50
),
q_top_tag as (
  select te.QuestionId, te.tag
  from tag_explode te
  join top_tags tt on tt.tag = te.tag
),
asker_profile as (
  select
    rq.QuestionId,
    u.Id as AskerId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    usd.UserAgeDays,
    bb.GoldBadges,
    bb.SilverBadges,
    bb.BronzeBadges
  from recent_q rq
  left join Users u on u.Id = rq.OwnerUserId
  left join user_stats usd on usd.UserId = u.Id
  left join badges_by_asker bb on bb.UserId = u.Id
),
hour_of_day as (
  select
    rq.QuestionId,
    cast(date_part('hour', rq.CreationDate) as integer) as HourUTC
  from recent_q rq
),
pop_hour as (
  select
    hod.HourUTC,
    count(*) as QCount,
    avg(rq.Score) as AvgScoreHour
  from hour_of_day hod
  join recent_q rq on rq.QuestionId = hod.QuestionId
  group by hod.HourUTC
),
final as (
  select
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.Score as QScore,
    rq.ViewCount,
    rq.AnswerCount,
    string_agg(distinct qtt.tag, ',') as TopTags,
    coalesce(qv.NetVotes,0) as NetVotes,
    coalesce(qv.Favorites,0) as Favorites,
    coalesce(qv.TotalBounty,0) as TotalBounty,
    coalesce(av.NetAnswerVotes,0) as NetAnswerVotes,
    coalesce(cc.CommentCount,0) as CommentCount,
    coalesce(cc.PositiveComments,0) as PositiveComments,
    coalesce(ed.EditCount,0) as EditCount,
    coalesce(ed.SuggestedEditsApplied,0) as SuggestedEditsApplied,
    coalesce(ed.CloseVotesInPH,0) as CloseVotesInPH,
    coalesce(dl.LinkedRefs,0) as LinkedRefs,
    coalesce(dl.DuplicateRefs,0) as DuplicateRefs,
    coalesce(ad.DistinctAnswerers,0) as DistinctAnswerers,
    al.HoursToFirstAnswer,
    al.HoursToAcceptedAnswer,
    ap.AskerId,
    ap.Reputation as AskerReputation,
    ap.GoldBadges,
    ap.SilverBadges,
    ap.BronzeBadges,
    ap.UserAgeDays,
    qs.ComputedQuality,
    ph.AvgScoreHour as AvgScoreAtHour
  from recent_q rq
  left join q_votes qv on qv.QuestionId = rq.QuestionId
  left join a_votes av on av.QuestionId = rq.QuestionId
  left join comment_counts cc on cc.PostId = rq.QuestionId
  left join edits ed on ed.QuestionId = rq.QuestionId
  left join duplicate_links dl on dl.QuestionId = rq.QuestionId
  left join answerer_diversity ad on ad.QuestionId = rq.QuestionId
  left join accepted_latency al on al.QuestionId = rq.QuestionId
  left join asker_profile ap on ap.QuestionId = rq.QuestionId
  left join quality_score qs on qs.QuestionId = rq.QuestionId
  left join q_top_tag qtt on qtt.QuestionId = rq.QuestionId
  left join hour_of_day hod on hod.QuestionId = rq.QuestionId
  left join pop_hour ph on ph.HourUTC = hod.HourUTC
  group by
    rq.QuestionId, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.AnswerCount,
    qv.NetVotes, qv.Favorites, qv.TotalBounty, av.NetAnswerVotes, cc.CommentCount, cc.PositiveComments,
    ed.EditCount, ed.SuggestedEditsApplied, ed.CloseVotesInPH, dl.LinkedRefs, dl.DuplicateRefs,
    ad.DistinctAnswerers, al.HoursToFirstAnswer, al.HoursToAcceptedAnswer,
    ap.AskerId, ap.Reputation, ap.GoldBadges, ap.SilverBadges, ap.BronzeBadges, ap.UserAgeDays,
    qs.ComputedQuality, ph.AvgScoreHour
)
select
  f.*,
  rank() over (order by f.QSComputed desc nulls last) as QualityRank,
  -- replace ordered-set aggregate with percentile_cont median without OVER; compute median across final by a subquery
  (select percentile_cont(0.5) within group (order by QScore)
   from final) as GlobalMedianScore
from (
  select
    final.*,
    final.ComputedQuality as QSComputed
  from final
) f
order by f.QSComputed desc nulls last, f.ViewCount desc
limit 500;