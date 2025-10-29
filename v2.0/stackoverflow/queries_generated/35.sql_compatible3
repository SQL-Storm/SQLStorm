with
q as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    coalesce(nullif(trim(p.Title), ''), '[untitled]') as Title,
    string_to_array(substring(p.Tags from 2 for greatest(length(p.Tags)-2,0)), '><') as TagArray
  from Posts p
  where p.PostTypeId = 1
),
answers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn_by_score,
    row_number() over (partition by a.ParentId order by a.CreationDate asc) as rn_by_time
  from Posts a
  where a.PostTypeId = 2
),
q_stats as (
  select
    q.QuestionId,
    count(ans.AnswerId) as AnswerCnt,
    sum(case when ans.Score > 0 then 1 else 0 end) as PosAnswerCnt,
    max(ans.Score) as MaxAnswerScore,
    min(ans.CreationDate) as FirstAnswerAt,
    avg(ans.Score) as AvgAnswerScore
  from q
  left join answers ans on ans.QuestionId = q.QuestionId
  group by q.QuestionId
),
accepts as (
  select
    q.QuestionId,
    aa.AnswerId as AcceptedId,
    aa.Score as AcceptedScore,
    aa.CreationDate as AcceptedAt,
    case when aa.rn_by_score = 1 then 1 else 0 end as AcceptedIsTopByScore,
    case when aa.rn_by_time = 1 then 1 else 0 end as AcceptedIsFirstByTime
  from q
  left join answers aa on aa.AnswerId = q.AcceptedAnswerId
),
tag_expanded as (
  select
    q.QuestionId,
    lower(trim(t)) as tag
  from q,
  lateral unnest(q.TagArray) as t
),
primary_lang as (
  select
    te.QuestionId,
    min(te.tag) filter (where te.tag in ('python','java','javascript','c#','c++','php','go','rust','ruby','swift','kotlin','typescript','sql','scala')) as MajorTag
  from tag_expanded te
  group by te.QuestionId
),
votes_agg as (
  select
    v.PostId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal
  from Votes v
  join Posts p on p.Id = v.PostId and p.PostTypeId = 1
  group by v.PostId
),
edits as (
  select
    ph.PostId as QuestionId,
    count(case when ph.PostHistoryTypeId in (4,5,6) then 1 end) as EditCount,
    max(ph.CreationDate) as LastEditAt
  from PostHistory ph
  join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
  group by ph.PostId
),
closures as (
  select
    ph.PostId as QuestionId,
    min(ph.CreationDate) as FirstClosedAt,
    max(ph.CreationDate) as LastClosedAt,
    count(*) as CloseEvents,
    max(case when ph.Comment ~ '^[0-9]+$' then ph.Comment else null end) as LastCloseReasonId
  from PostHistory ph
  where ph.PostHistoryTypeId = 10
  group by ph.PostId
),
dupes as (
  select
    pl.PostId as QuestionId,
    count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateLinks,
    count(case when pl.LinkTypeId = 1 then 1 end) as RelatedLinks
  from PostLinks pl
  group by pl.PostId
),
commenter_diversity as (
  select
    c.PostId as QuestionId,
    count(*) as CommentCount,
    count(distinct coalesce(c.UserId, -1)) as DistinctCommentUsers,
    max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
user_norms as (
  select
    u.Id as UserId,
    u.Reputation,
    coalesce(nullif(trim(u.Location),''), 'Unknown') as NormLocation,
    coalesce(u.UpVotes,0) - coalesce(u.DownVotes,0) as NetVotes,
    width_bucket(u.Reputation, 0, 100000, 10) as RepDecile
  from Users u
),
tag_metrics as (
  select
    te.tag,
    count(distinct te.QuestionId) as TaggedQuestions,
    avg(qs.AnswerCnt) as AvgAnswersPerTag,
    percentile_cont(0.5) within group (order by coalesce(qs.AnswerCnt,0)) as P50AnswersPerTag
  from tag_expanded te
  left join q_stats qs on qs.QuestionId = te.QuestionId
  group by te.tag
),
question_age as (
  select
    q.QuestionId,
    extract(epoch from (timestamp '2024-10-01 12:34:56' - q.CreationDate))/86400.0 as AgeDays
  from q
),
fastest_answer as (
  select distinct on (a.QuestionId)
    a.QuestionId,
    a.AnswerId,
    a.CreationDate as FirstAnswerAt
  from answers a
  order by a.QuestionId, a.CreationDate
),
time_to_first as (
  select
    q.QuestionId,
    extract(epoch from (fa.FirstAnswerAt - q.CreationDate))/3600.0 as HoursToFirstAnswer
  from q
  left join fastest_answer fa on fa.QuestionId = q.QuestionId
),
user_badges as (
  select
    b.UserId,
    count(case when b.Class = 1 then 1 end) as Gold,
    count(case when b.Class = 2 then 1 end) as Silver,
    count(case when b.Class = 3 then 1 end) as Bronze,
    count(case when b.TagBased = true then 1 end) as TagBadges
  from Badges b
  group by b.UserId
),
leader_answer as (
  select
    a.QuestionId,
    a.AnswerId as TopAnswerId,
    a.Score as TopAnswerScore
  from answers a
  where a.rn_by_score = 1
),
question_quality as (
  select
    q.QuestionId,
    case
      when q.ViewCount >= 10000 and q.Score >= 10 then 'high'
      when q.ViewCount >= 1000 and q.Score >= 0 then 'medium'
      else 'low'
    end as QualityBand
  from q
),
filtered as (
  select
    q.QuestionId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.AcceptedAnswerId,
    q.Title,
    q.TagArray,
    qs.AnswerCnt,
    qs.PosAnswerCnt,
    qs.MaxAnswerScore,
    qs.FirstAnswerAt,
    qs.AvgAnswerScore,
    coalesce(v.UpVotes,0) as QUp,
    coalesce(v.DownVotes,0) as QDown,
    coalesce(v.Favorites,0) as QFavs,
    coalesce(v.BountyTotal,0) as QBounty,
    coalesce(e.EditCount,0) as EditCount,
    e.LastEditAt,
    cl.FirstClosedAt,
    cl.LastClosedAt,
    coalesce(cl.CloseEvents,0) as CloseEvents,
    cl.LastCloseReasonId,
    coalesce(d.DuplicateLinks,0) as DuplicateLinks,
    coalesce(d.RelatedLinks,0) as RelatedLinks,
    coalesce(cd.CommentCount,0) as CommentCount,
    coalesce(cd.DistinctCommentUsers,0) as DistinctCommentUsers,
    cd.LastCommentAt,
    pl.MajorTag,
    tm.TaggedQuestions as MajorTagVolume,
    tm.AvgAnswersPerTag as MajorTagAvgAnswers,
    ttf.HoursToFirstAnswer,
    qa.AgeDays,
    la.TopAnswerId,
    la.TopAnswerScore,
    ac.AcceptedId,
    ac.AcceptedScore,
    ac.AcceptedAt,
    ac.AcceptedIsTopByScore,
    ac.AcceptedIsFirstByTime,
    uq.Reputation as OwnerRep,
    ub.Gold as OwnerGoldBadges,
    ub.Silver as OwnerSilverBadges,
    ub.Bronze as OwnerBronzeBadges,
    ub.TagBadges as OwnerTagBadges,
    qq.QualityBand
  from q
  left join q_stats qs on qs.QuestionId = q.QuestionId
  left join votes_agg v on v.QuestionId = q.QuestionId
  left join edits e on e.QuestionId = q.QuestionId
  left join closures cl on cl.QuestionId = q.QuestionId
  left join dupes d on d.QuestionId = q.QuestionId
  left join commenter_diversity cd on cd.QuestionId = q.QuestionId
  left join primary_lang pl on pl.QuestionId = q.QuestionId
  left join tag_metrics tm on tm.tag = coalesce(pl.MajorTag, 'unknown')
  left join time_to_first ttf on ttf.QuestionId = q.QuestionId
  left join question_age qa on qa.QuestionId = q.QuestionId
  left join leader_answer la on la.QuestionId = q.QuestionId
  left join accepts ac on ac.QuestionId = q.QuestionId
  left join user_norms uq on uq.UserId = q.OwnerUserId
  left join user_badges ub on ub.UserId = q.OwnerUserId
  left join question_quality qq on qq.QuestionId = q.QuestionId
  where
    (
      (coalesce(q.Score,0) - coalesce(v.DownVotes,0) + coalesce(v.UpVotes,0)) >= 5
      or (coalesce(q.ViewCount,0) >= 1000 and coalesce(qs.AnswerCnt,0) >= 1)
      or (ac.AcceptedId is not null and coalesce(ac.AcceptedScore,0) >= 0)
    )
    and (
      pl.MajorTag is null
      or tm.TaggedQuestions is null
      or tm.TaggedQuestions > 100
      or (tm.AvgAnswersPerTag is not null and tm.AvgAnswersPerTag >= 1.5)
    )
),
ranked as (
  select
    f.QuestionId,
    f.CreationDate,
    f.Score,
    f.ViewCount,
    f.OwnerUserId,
    f.AcceptedAnswerId,
    f.Title,
    f.TagArray,
    f.AnswerCnt,
    f.PosAnswerCnt,
    f.MaxAnswerScore,
    f.FirstAnswerAt,
    f.AvgAnswerScore,
    f.QUp,
    f.QDown,
    f.QFavs,
    f.QBounty,
    f.EditCount,
    f.LastEditAt,
    f.FirstClosedAt,
    f.LastClosedAt,
    f.CloseEvents,
    f.LastCloseReasonId,
    f.DuplicateLinks,
    f.RelatedLinks,
    f.CommentCount,
    f.DistinctCommentUsers,
    f.LastCommentAt,
    f.MajorTag,
    f.MajorTagVolume,
    f.MajorTagAvgAnswers,
    f.HoursToFirstAnswer,
    f.AgeDays,
    f.TopAnswerId,
    f.TopAnswerScore,
    f.AcceptedId,
    f.AcceptedScore,
    f.AcceptedAt,
    f.AcceptedIsTopByScore,
    f.AcceptedIsFirstByTime,
    f.OwnerRep,
    f.OwnerGoldBadges,
    f.OwnerSilverBadges,
    f.OwnerBronzeBadges,
    f.OwnerTagBadges,
    f.QualityBand,
    dense_rank() over (order by coalesce(f.QBounty,0) desc, coalesce(f.Score,0) desc, coalesce(f.ViewCount,0) desc) as RnkByBountyScoreViews,
    row_number() over (partition by coalesce(f.MajorTag,'[none]') order by coalesce(f.Score, -2147483648) desc, coalesce(f.ViewCount, -1) desc) as RowInTagByScore,
    ntile(4) over (order by coalesce(f.HoursToFirstAnswer, 1e9)) as QuartileByResponseSpeed,
    sum(coalesce(f.CommentCount,0)) over (partition by coalesce(f.MajorTag,'[none]')) as TotalCommentsInTag
  from filtered f
),
dupe_targets as (
  select
    pl.RelatedPostId as TargetQuestionId,
    count(case when pl.LinkTypeId = 3 then 1 end) as TimesMarkedDuplicateTarget
  from PostLinks pl
  join Posts p on p.Id = pl.RelatedPostId and p.PostTypeId = 1
  group by pl.RelatedPostId
),
final as (
  select
    r.QuestionId,
    r.Title,
    coalesce(r.MajorTag,'[none]') as MajorTag,
    r.Score,
    r.ViewCount,
    r.AnswerCnt,
    r.PosAnswerCnt,
    r.TopAnswerScore,
    r.AcceptedScore,
    r.AcceptedIsTopByScore,
    r.AcceptedIsFirstByTime,
    r.QUp,
    r.QDown,
    r.QFavs,
    r.QBounty,
    r.EditCount,
    r.CloseEvents,
    r.DuplicateLinks,
    r.RelatedLinks,
    r.CommentCount,
    r.DistinctCommentUsers,
    r.HoursToFirstAnswer,
    r.AgeDays,
    r.OwnerRep,
    r.OwnerGoldBadges,
    r.OwnerSilverBadges,
    r.OwnerBronzeBadges,
    r.OwnerTagBadges,
    r.QualityBand,
    r.RnkByBountyScoreViews,
    r.RowInTagByScore,
    r.QuartileByResponseSpeed,
    r.TotalCommentsInTag,
    dt.TimesMarkedDuplicateTarget,
    case
      when r.AcceptedId is null and r.AnswerCnt = 0 then 'unanswered'
      when r.AcceptedId is null and r.AnswerCnt > 0 then 'no-accept'
      when r.AcceptedId is not null and r.AcceptedIsTopByScore = 1 then 'accepted-top'
      else 'accepted-not-top'
    end as AnswerOutcomeCategory,
    case
      when r.CloseEvents > 0 then 'closed'
      when r.DuplicateLinks > 0 then 'duplicate-linked'
      when r.EditCount >= 3 then 'heavily-edited'
      else 'normal'
    end as ModerationState
  from ranked r
  left join dupe_targets dt on dt.TargetQuestionId = r.QuestionId
)
select *
from final
where
  (
    (MajorTag in ('python','javascript','java') and (AcceptedIsTopByScore = 1 or (TopAnswerScore >= 5 and coalesce(AcceptedScore,-999) >= -2)))
    or (MajorTag not in ('python','javascript','java') or MajorTag is null)
  )
  and (
    (QualityBand = 'high' and QBounty >= 0)
    or (QualityBand = 'medium' and CommentCount >= 1)
    or (QualityBand = 'low' and (HoursToFirstAnswer is null or HoursToFirstAnswer > 24))
  )
order by
  RnkByBountyScoreViews asc,
  RowInTagByScore asc,
  QuestionId desc
limit 500;