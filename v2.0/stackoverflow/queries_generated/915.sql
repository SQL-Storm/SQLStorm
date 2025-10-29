-- {"query": "915.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3969} 
with
q_posts as (
  select
    p.Id as QuestionId,
    p.OwnerUserId,
    p.Score as QScore,
    p.ViewCount,
    p.CreationDate as QCreated,
    p.AcceptedAnswerId,
    p.Tags,
    p.Title
  from Posts p
  where p.PostTypeId = 1
),
a_posts as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswerOwnerId,
    a.Score as AScore,
    a.CreationDate as ACreated
  from Posts a
  where a.PostTypeId = 2
),
q_activity as (
  select
    ph.PostId as QuestionId,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditDate,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesRecorded,
    count(*) filter (where ph.PostHistoryTypeId in (35,36)) as Migrations
  from PostHistory ph
  join Posts qp on qp.Id = ph.PostId and qp.PostTypeId = 1
  group by ph.PostId
),
q_comments as (
  select
    c.PostId as QuestionId,
    count(*) as CommentCount,
    coalesce(sum(case when c.Score > 0 then 1 else 0 end),0) as PositiveCommentCount,
    min(c.CreationDate) as FirstCommentAt,
    max(c.CreationDate) as LastCommentAt
  from Comments c
  join Posts qp on qp.Id = c.PostId and qp.PostTypeId = 1
  group by c.PostId
),
q_votes as (
  select
    v.PostId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal
  from Votes v
  join Posts qp on qp.Id = v.PostId and qp.PostTypeId = 1
  group by v.PostId
),
a_votes as (
  select
    a.ParentId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as AnswerUpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as AnswerDownVotes
  from Votes v
  join Posts a on a.Id = v.PostId and a.PostTypeId = 2
  group by a.ParentId
),
answers_ranked as (
  select
    a.*,
    row_number() over (partition by a.QuestionId order by a.Score desc, a.CreationDate asc, a.Id asc) as rn_by_score,
    row_number() over (partition by a.QuestionId order by a.CreationDate asc, a.Id asc) as rn_by_time
  from a_posts a
),
per_user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate,
    u.UpVotes as UserUpVotes,
    u.DownVotes as UserDownVotes,
    u.Views as ProfileViews,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    count(b.Id) as TotalBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, u.Views
),
tag_expanded as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, nullif(length(q.Tags)-2, -1)), '><')) as tag
  from q_posts q
  where q.Tags is not null
),
tag_popularity as (
  select
    te.QuestionId,
    te.tag,
    t.Count as GlobalTagCount,
    t.IsModeratorOnly,
    t.IsRequired
  from tag_expanded te
  left join Tags t on lower(t.TagName) = lower(te.tag)
),
question_tag_agg as (
  select
    te.QuestionId,
    min(case when tp.IsModeratorOnly then 1 else 0 end) as HasModOnlyTag,
    min(case when tp.IsRequired then 1 else 0 end) as HasRequiredTag,
    coalesce(avg(nullif(tp.GlobalTagCount,0)), 0) as AvgGlobalTagCount,
    count(*) as TagCount,
    string_agg(te.tag, '|' order by te.tag) as TagList
  from tag_expanded te
  left join tag_popularity tp on tp.QuestionId = te.QuestionId and tp.tag = te.tag
  group by te.QuestionId
),
dup_links as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(*) filter (where pl.LinkTypeId = 1) as RelatedLinks
  from PostLinks pl
  join Posts qp on qp.Id = pl.PostId and qp.PostTypeId = 1
  group by pl.PostId
),
first_activity as (
  select
    q.QuestionId,
    least(
      q.QCreated,
      aq.MinAnswerAt,
      qc.FirstCommentAt,
      qa.LastEditDate
    ) as FirstActivityAt
  from q_posts q
  left join (
    select QuestionId, min(ACreated) as MinAnswerAt
    from a_posts
    group by QuestionId
  ) aq on aq.QuestionId = q.QuestionId
  left join q_comments qc on qc.QuestionId = q.QuestionId
  left join q_activity qa on qa.QuestionId = q.QuestionId
),
accepted_answer_info as (
  select
    q.QuestionId,
    a.AnswerId as AcceptedAnswerId,
    a.AScore as AcceptedScore,
    a.ACreated as AcceptedCreated,
    case when a.AnswerId is not null then 1 else 0 end as HasAccepted
  from q_posts q
  left join a_posts a on a.Id = q.AcceptedAnswerId
),
best_answer_info as (
  select
    ar.QuestionId,
    ar.AnswerId as BestAnswerId,
    ar.AScore as BestScore,
    ar.ACreated as BestCreated
  from answers_ranked ar
  where ar.rn_by_score = 1
),
fastest_answer_info as (
  select
    ar.QuestionId,
    ar.AnswerId as FirstAnswerId,
    ar.AScore as FirstAnswerScore,
    ar.ACreated as FirstAnswerCreated
  from answers_ranked ar
  where ar.rn_by_time = 1
),
owner_enriched as (
  select
    q.QuestionId,
    u.UserId as OwnerUserId,
    u.Reputation as OwnerRep,
    u.TotalBadges,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges
  from q_posts q
  left join per_user_stats u on u.UserId = q.OwnerUserId
),
answerers_agg as (
  select
    a.QuestionId,
    count(distinct a.AnswerOwnerId) as DistinctAnswerers,
    avg(u.Reputation)::numeric as AvgAnswererRep,
    max(u.Reputation) as MaxAnswererRep,
    min(u.Reputation) as MinAnswererRep
  from a_posts a
  left join Users u on u.Id = a.AnswerOwnerId
  group by a.QuestionId
),
question_engagement as (
  select
    q.QuestionId,
    coalesce(qv.UpVotes,0) as QUp,
    coalesce(qv.DownVotes,0) as QDown,
    coalesce(qv.Favorites,0) as QFav,
    coalesce(qv.BountyTotal,0) as QBounty,
    coalesce(av.AnswerUpVotes,0) as AUp,
    coalesce(av.AnswerDownVotes,0) as ADown
  from q_posts q
  left join q_votes qv on qv.QuestionId = q.QuestionId
  left join a_votes av on av.QuestionId = q.QuestionId
),
question_answer_counts as (
  select
    q.QuestionId,
    count(a.AnswerId) as AnswerCount,
    sum(case when a.AScore > 0 then 1 else 0 end) as PositiveAnswers,
    sum(case when a.AScore < 0 then 1 else 0 end) as NegativeAnswers
  from q_posts q
  left join a_posts a on a.QuestionId = q.QuestionId
  group by q.QuestionId
),
quality_signals as (
  select
    q.QuestionId,
    case
      when qe.QUp - qe.QDown >= 5 and qa.HasAccepted = 1 then 'high'
      when qe.QUp - qe.QDown >= 0 and qa.HasAccepted = 0 then 'medium'
      else 'low'
    end as QualityBand,
    (coalesce(qc.CommentCount,0) + coalesce(qa2.AnswerCount,0)) as InteractionCount,
    (coalesce(qe.QUp,0) + coalesce(qe.AUp,0)) - (coalesce(qe.QDown,0) + coalesce(qe.ADown,0)) as NetVotes
  from q_posts q
  left join accepted_answer_info qa on qa.QuestionId = q.QuestionId
  left join q_comments qc on qc.QuestionId = q.QuestionId
  left join question_answer_counts qa2 on qa2.QuestionId = q.QuestionId
  left join question_engagement qe on qe.QuestionId = q.QuestionId
),
outer_union as (
  select QuestionId, 'accepted' as kind, AcceptedAnswerId as ref_id from accepted_answer_info where AcceptedAnswerId is not null
  union all
  select QuestionId, 'best' as kind, BestAnswerId from best_answer_info
  union all
  select QuestionId, 'first' as kind, FirstAnswerId from fastest_answer_info
),
answer_flags as (
  select
    ou.QuestionId,
    max(case when ou.kind = 'accepted' then 1 else 0 end) as hasAcceptedRef,
    max(case when ou.kind = 'best' then 1 else 0 end) as hasBestRef,
    max(case when ou.kind = 'first' then 1 else 0 end) as hasFirstRef,
    count(distinct ou.ref_id) as distinctRefCount
  from outer_union ou
  group by ou.QuestionId
),
question_time_spans as (
  select
    q.QuestionId,
    extract(epoch from (coalesce(aa.AcceptedCreated, ba.BestCreated, fa.FirstAnswerCreated) - q.QCreated)) as SecsToFirstResolution,
    extract(epoch from (qa.LastEditDate - q.QCreated)) as SecsToLastEdit,
    extract(epoch from (fc.FirstActivityAt - q.QCreated)) as SecsToFirstActivity
  from q_posts q
  left join accepted_answer_info aa on aa.QuestionId = q.QuestionId
  left join best_answer_info ba on ba.QuestionId = q.QuestionId
  left join fastest_answer_info fa on fa.QuestionId = q.QuestionId
  left join q_activity qa on qa.QuestionId = q.QuestionId
  left join first_activity fc on fc.QuestionId = q.QuestionId
),
scored as (
  select
    q.QuestionId,
    q.Title,
    lower(coalesce(q.Title,'')) like any (array['%how to%','%best way%','%why%']) as IsHowTo,
    coalesce(q.QScore,0) as QScore,
    coalesce(q.ViewCount,0) as Views,
    coalesce(eng.QUp,0) as QUp,
    coalesce(eng.QDown,0) as QDown,
    coalesce(eng.QFav,0) as QFav,
    coalesce(eng.QBounty,0) as QBounty,
    coalesce(qa.HasAccepted,0) as HasAccepted,
    coalesce(bi.BestScore,0) as BestScore,
    coalesce(fi.FirstAnswerScore,0) as FirstAnswerScore,
    coalesce(ts.SecsToFirstResolution, null) as SecsToFirstResolution,
    coalesce(ts.SecsToLastEdit, null) as SecsToLastEdit,
    coalesce(ts.SecsToFirstActivity, null) as SecsToFirstActivity,
    coalesce(qa2.AnswerCount,0) as AnswerCount,
    coalesce(qc.CommentCount,0) as CommentCount,
    coalesce(qta.TagCount,0) as TagCount,
    coalesce(qta.AvgGlobalTagCount,0) as AvgGlobalTagCount,
    coalesce(dl.DuplicateLinks,0) as DuplicateLinks,
    coalesce(dl.RelatedLinks,0) as RelatedLinks,
    coalesce(af.distinctRefCount,0) as DistinctAnswerRefs,
    coalesce(af.hasAcceptedRef,0) as HasAcceptedRef,
    coalesce(af.hasBestRef,0) as HasBestRef,
    coalesce(af.hasFirstRef,0) as HasFirstRef,
    coalesce(oe.OwnerRep,0) as OwnerRep,
    coalesce(oe.TotalBadges,0) as OwnerBadges,
    coalesce(aa.DistinctAnswerers,0) as DistinctAnswerers,
    coalesce(qs.NetVotes,0) as NetVotes,
    qs.QualityBand,
    case
      when qta.HasModOnlyTag = 1 then 'mod-only'
      when qta.HasRequiredTag = 1 then 'required'
      else 'normal'
    end as TagPolicy,
    case
      when q.Tags is null then 1
      when length(q.Tags) <= 2 then 1
      else 0
    end as IsUntaggedOrEmpty
  from q_posts q
  left join question_engagement eng on eng.QuestionId = q.QuestionId
  left join accepted_answer_info qa on qa.QuestionId = q.QuestionId
  left join best_answer_info bi on bi.QuestionId = q.QuestionId
  left join fastest_answer_info fi on fi.QuestionId = q.QuestionId
  left join question_time_spans ts on ts.QuestionId = q.QuestionId
  left join question_answer_counts qa2 on qa2.QuestionId = q.QuestionId
  left join q_comments qc on qc.QuestionId = q.QuestionId
  left join question_tag_agg qta on qta.QuestionId = q.QuestionId
  left join dup_links dl on dl.QuestionId = q.QuestionId
  left join answer_flags af on af.QuestionId = q.QuestionId
  left join owner_enriched oe on oe.QuestionId = q.QuestionId
  left join answerers_agg aa on aa.QuestionId = q.QuestionId
  left join quality_signals qs on qs.QuestionId = q.QuestionId
),
ranked as (
  select
    s.*,
    row_number() over (order by
      (coalesce(s.QUp,0) + coalesce(s.BestScore,0) + coalesce(s.OwnerRep,0)/100.0 + coalesce(s.QFav,0)*2 - coalesce(s.QDown,0) - case when s.HasAccepted=0 then 1 else 0 end) desc,
      s.Views desc,
      s.AnswerCount desc,
      s.QuestionId asc
    ) as GlobalRank,
    dense_rank() over (partition by s.QualityBand order by s.Views desc, s.NetVotes desc, s.AnswerCount desc) as RankWithinBand
  from scored s
),
band_thresholds as (
  select
    QualityBand,
    percentile_disc(array[0.25,0.5,0.75]) within group (order by Views) as view_quartiles
  from ranked
  group by QualityBand
),
finalized as (
  select
    r.*,
    bt.view_quartiles[1] as Views_Q1,
    bt.view_quartiles[2] as Views_Q2,
    bt.view_quartiles[3] as Views_Q3,
    case
      when r.Views >= bt.view_quartiles[3] then 'top'
      when r.Views >= bt.view_quartiles[2] then 'upper'
      when r.Views >= bt.view_quartiles[1] then 'middle'
      else 'lower'
    end as ViewsBand
  from ranked r
  left join band_thresholds bt on bt.QualityBand = r.QualityBand
)
select
  f.QuestionId,
  f.GlobalRank,
  f.RankWithinBand,
  f.QualityBand,
  f.ViewsBand,
  f.Views,
  f.QScore,
  f.NetVotes,
  f.QUp, f.QDown, f.QFav, f.QBounty,
  f.AnswerCount, f.CommentCount, f.DistinctAnswerers,
  f.HasAccepted, f.HasAcceptedRef, f.HasBestRef, f.HasFirstRef,
  f.SecsToFirstResolution, f.SecsToLastEdit, f.SecsToFirstActivity,
  f.TagCount, f.TagPolicy, f.IsUntaggedOrEmpty, f.AvgGlobalTagCount,
  f.DuplicateLinks, f.RelatedLinks, f.DistinctAnswerRefs,
  f.OwnerRep, f.OwnerBadges,
  coalesce(nullif(trim(both ' ' from replace(replace(replace(f.Title, E'\n',' '), E'\r',' '), E'\t',' '))),'(no title)') as NormalizedTitle
from finalized f
where
  coalesce(f.Views,0) > 0
  and (f.IsUntaggedOrEmpty = 0 or f.Views > f.Views_Q1)
  and (f.TagPolicy <> 'mod-only' or f.OwnerRep >= 2000)
  and not (f.QDown > f.QUp and f.AnswerCount = 0)
order by
  f.GlobalRank asc
limit 500;