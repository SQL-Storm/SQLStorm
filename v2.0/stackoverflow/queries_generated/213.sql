-- {"query": "213.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2972} 
with recent_questions as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answer_stats as (
  select
    a.ParentId as QuestionId,
    count(*) as AnswerTotal,
    sum(case when a.Score > 0 then 1 else 0 end) as PosAnswers,
    avg(a.Score::numeric) as AvgAnswerScore,
    max(a.CreationDate) as LastAnswerDate
  from Posts a
  where a.PostTypeId = 2
  group by a.ParentId
),
accepted_answers as (
  select
    q.Id as QuestionId,
    q.AcceptedAnswerId,
    aa.Score as AcceptedScore,
    aa.OwnerUserId as AcceptedOwnerId,
    aa.CreationDate as AcceptedCreationDate
  from Posts q
  left join Posts aa on aa.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1
),
question_vote_pivot as (
  select
    v.PostId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
  from Votes v
  join Posts p on p.Id = v.PostId and p.PostTypeId = 1
  group by v.PostId
),
comment_activity as (
  select
    c.PostId as QuestionId,
    count(*) as CommentCount,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
tag_explode as (
  select
    rq.QuestionId,
    unnest(string_to_array(substring(rq.Tags from 2 for length(rq.Tags)-2), '><')) as tag
  from recent_questions rq
  where rq.Tags is not null
),
tag_quality as (
  select
    te.QuestionId,
    avg(t.Count::numeric) as AvgTagPopularity,
    max(case when t.IsModeratorOnly = 1 then 1 else 0 end) as HasModOnlyTag,
    max(case when t.IsRequired = 1 then 1 else 0 end) as HasRequiredTag
  from tag_explode te
  left join Tags t on t.TagName = te.tag
  group by te.QuestionId
),
user_profile as (
  select
    u.Id,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    coalesce(nullif(bc.BadgeCountsJson, ''), '{"Gold":0,"Silver":0,"Bronze":0}') as BadgeCountsJson
  from Users u
  left join (
    select
      b.UserId,
      json_build_object(
        'Gold', sum(case when b.Class = 1 then 1 else 0 end),
        'Silver', sum(case when b.Class = 2 then 1 else 0 end),
        'Bronze', sum(case when b.Class = 3 then 1 else 0 end)
      )::text as BadgeCountsJson
    from Badges b
    group by b.UserId
  ) bc on bc.UserId = u.Id
),
close_events as (
  select
    ph.PostId as QuestionId,
    min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstClosedDate,
    max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenDate,
    max(case when ph.PostHistoryTypeId = 10 then try_cast(ph.Comment as int) end) as LastCloseReasonId
  from PostHistory ph
  where ph.PostHistoryTypeId in (10, 11)
  group by ph.PostId
),
dup_links as (
  select
    pl.PostId as DuplicateId,
    pl.RelatedPostId as CanonicalId,
    min(pl.CreationDate) as FirstDupLinkDate
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId, pl.RelatedPostId
),
question_engagement as (
  select
    rq.QuestionId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.Title,
    rq.AnswerCount,
    qs.UpVotes,
    qs.DownVotes,
    qs.Favorites,
    ca.CommentCount,
    ca.LastCommentDate,
    as2.AnswerTotal,
    as2.PosAnswers,
    as2.AvgAnswerScore,
    as2.LastAnswerDate,
    coalesce(tq.AvgTagPopularity, 0) as AvgTagPopularity,
    tq.HasModOnlyTag,
    tq.HasRequiredTag,
    ce.FirstClosedDate,
    ce.LastReopenDate,
    ce.LastCloseReasonId,
    da.CanonicalId as DuplicateOfId,
    da.FirstDupLinkDate
  from recent_questions rq
  left join question_vote_pivot qs on qs.QuestionId = rq.QuestionId
  left join comment_activity ca on ca.QuestionId = rq.QuestionId
  left join answer_stats as2 on as2.QuestionId = rq.QuestionId
  left join tag_quality tq on tq.QuestionId = rq.QuestionId
  left join close_events ce on ce.QuestionId = rq.QuestionId
  left join dup_links da on da.DuplicateId = rq.QuestionId
),
owner_enriched as (
  select
    qe.*,
    u.Reputation as OwnerReputation,
    u.UpVotes as OwnerUpVotes,
    u.DownVotes as OwnerDownVotes,
    u.ProfileViews as OwnerProfileViews,
    u.BadgeCountsJson as OwnerBadgesJson
  from question_engagement qe
  left join user_profile u on u.Id = qe.OwnerUserId
),
accepted_enriched as (
  select
    oe.*,
    ac.AcceptedAnswerId,
    ac.AcceptedScore,
    ac.AcceptedOwnerId,
    ac.AcceptedCreationDate
  from owner_enriched oe
  left join accepted_answers ac on ac.QuestionId = oe.QuestionId
),
accepted_owner_profile as (
  select
    u.Id,
    u.Reputation as AcceptedOwnerReputation,
    u.UpVotes as AcceptedOwnerUpVotes,
    u.DownVotes as AcceptedOwnerDownVotes,
    u.ProfileViews as AcceptedOwnerProfileViews,
    u.BadgeCountsJson as AcceptedOwnerBadgesJson
  from user_profile u
),
rankings as (
  select
    ae.*,
    row_number() over (order by coalesce(ae.ViewCount,0) desc, coalesce(ae.Score,0) desc, ae.CreationDate desc) as RN_Global,
    dense_rank() over (partition by case when ae.HasModOnlyTag = 1 then 'Mod' when ae.HasRequiredTag = 1 then 'Req' else 'Normal' end
                       order by coalesce(ae.Favorites,0) desc, coalesce(ae.AvgAnswerScore,0) desc) as DR_ByTagType,
    percentile_disc(0.5) within group (order by coalesce(ae.AvgAnswerScore,0)) over () as Median_AvgAnswerScore
  from accepted_enriched ae
),
normalized as (
  select
    r.*,
    case when r.ViewCount is null or r.ViewCount = 0 then 0
         else (r.UpVotes - coalesce(r.DownVotes,0))::numeric / r.ViewCount end as VoteEfficiency,
    case when r.AnswerTotal is null or r.AnswerTotal = 0 then null
         else r.PosAnswers::numeric / r.AnswerTotal end as PositiveAnswerRatio,
    case
      when r.FirstClosedDate is not null and (r.LastReopenDate is null or r.FirstClosedDate > r.LastReopenDate) then 1
      else 0
    end as IsCurrentlyClosed,
    case when r.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    case when r.DuplicateOfId is not null then 1 else 0 end as IsDuplicate,
    extract(epoch from (now() - r.CreationDate)) / 3600.0 as AgeHours
  from rankings r
),
scored as (
  select
    n.*,
    (
      coalesce(n.VoteEfficiency, 0) * 2
      + coalesce(n.Favorites, 0) * 0.5
      + coalesce(n.AvgAnswerScore, 0) * 1.5
      + case when n.HasAccepted = 1 then 5 else 0 end
      + least(coalesce(n.AvgTagPopularity,0)/1000.0, 10)
      - case when n.IsCurrentlyClosed = 1 then 10 else 0 end
      - case when n.IsDuplicate = 1 then 3 else 0 end
      + case when n.AgeHours < 24 then 2 when n.AgeHours < 168 then 1 else 0 end
    ) as CompositeScore
  from normalized n
),
with_accepted_owner as (
  select
    s.*,
    ap.AcceptedOwnerReputation,
    ap.AcceptedOwnerUpVotes,
    ap.AcceptedOwnerDownVotes,
    ap.AcceptedOwnerProfileViews,
    ap.AcceptedOwnerBadgesJson
  from scored s
  left join accepted_owner_profile ap on ap.Id = s.AcceptedOwnerId
),
stringified as (
  select
    w.*,
    coalesce(nullif(w.Title, ''), concat('[untitled #', w.QuestionId::text, ']')) as DisplayTitle,
    trim(both ' ' from regexp_replace(coalesce(w.Title, ''), '\s+', ' ', 'g')) as TitleNormalized,
    case
      when w.Tags is null then '{}'
      else array_to_string(string_to_array(substring(w.Tags from 2 for length(w.Tags)-2), '><'), ',')
    end as TagsCsv,
    case
      when w.OwnerBadgesJson is null then '{"Gold":0,"Silver":0,"Bronze":0}'
      else w.OwnerBadgesJson
    end as OwnerBadgesSafe,
    case
      when w.AcceptedOwnerBadgesJson is null then '{"Gold":0,"Silver":0,"Bronze":0}'
      else w.AcceptedOwnerBadgesJson
    end as AcceptedBadgesSafe
  from with_accepted_owner w
),
bucketed as (
  select
    s.*,
    width_bucket(coalesce(s.CompositeScore,0), -20.0, 50.0, 10) as ScoreBucket,
    case
      when coalesce(s.ViewCount,0) >= 100000 then 'V5'
      when coalesce(s.ViewCount,0) >= 20000 then 'V4'
      when coalesce(s.ViewCount,0) >= 5000 then 'V3'
      when coalesce(s.ViewCount,0) >= 1000 then 'V2'
      when coalesce(s.ViewCount,0) > 0 then 'V1'
      else 'V0'
    end as ViewBucket
  from stringified s
),
final_rank as (
  select
    b.*,
    rank() over (order by b.CompositeScore desc, coalesce(b.ViewCount,0) desc, coalesce(b.Score,0) desc, b.CreationDate desc) as RankFinal,
    row_number() over (partition by b.ViewBucket order by b.CompositeScore desc) as RN_ByViewBucket
  from bucketed b
)
select
  fr.QuestionId,
  fr.DisplayTitle,
  fr.TitleNormalized,
  fr.TagsCsv,
  fr.OwnerUserId,
  fr.OwnerReputation,
  fr.OwnerUpVotes,
  fr.OwnerDownVotes,
  fr.OwnerProfileViews,
  fr.OwnerBadgesSafe,
  fr.AcceptedAnswerId,
  fr.AcceptedScore,
  fr.AcceptedOwnerId,
  fr.AcceptedOwnerReputation,
  fr.AcceptedOwnerUpVotes,
  fr.AcceptedOwnerDownVotes,
  fr.AcceptedOwnerProfileViews,
  fr.AcceptedBadgesSafe,
  fr.Score,
  fr.ViewCount,
  fr.UpVotes,
  fr.DownVotes,
  fr.Favorites,
  fr.AnswerCount,
  fr.AnswerTotal,
  fr.PosAnswers,
  fr.PositiveAnswerRatio,
  fr.AvgAnswerScore,
  fr.LastAnswerDate,
  fr.CommentCount,
  fr.LastCommentDate,
  fr.AvgTagPopularity,
  fr.HasModOnlyTag,
  fr.HasRequiredTag,
  fr.FirstClosedDate,
  fr.LastReopenDate,
  fr.LastCloseReasonId,
  fr.DuplicateOfId,
  fr.FirstDupLinkDate,
  fr.IsCurrentlyClosed,
  fr.IsDuplicate,
  fr.HasAccepted,
  fr.AgeHours,
  fr.RN_Global,
  fr.DR_ByTagType,
  fr.Median_AvgAnswerScore,
  fr.ScoreBucket,
  fr.ViewBucket,
  fr.CompositeScore,
  fr.RankFinal,
  fr.RN_ByViewBucket
from final_rank fr
where (
    fr.CompositeScore > (
      select avg(CompositeScore) + stddev_pop(CompositeScore)
      from final_rank
    )
    or fr.RN_Global <= 100
    or (fr.ViewBucket in ('V5','V4') and fr.RN_ByViewBucket <= 50)
  )
order by fr.CompositeScore desc, fr.RankFinal asc, fr.QuestionId
limit 500;