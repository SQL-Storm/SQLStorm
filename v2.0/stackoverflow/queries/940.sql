with recent_questions as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName as OwnerDisplayName,
    coalesce(u.Location, 'Unknown') as OwnerLocation,
    row_number() over (partition by p.OwnerUserId order by p.CreationDate desc, p.Id desc) as rn_owner
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
question_stats as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.OwnerLocation,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.Tags,
    count(a.Id) filter (where a.PostTypeId = 2) as AnswerCount,
    max(a.Score) filter (where a.PostTypeId = 2) as MaxAnswerScore,
    avg(a.Score) filter (where a.PostTypeId = 2) as AvgAnswerScore,
    count(distinct c.Id) as CommentCount,
    sum(c.Score) as CommentScoreSum,
    count(*) filter (where v.VoteTypeId = 5) as FavoriteCountLegacy,
    sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotesFromVotes,
    max(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as MaxBountySeen
  from recent_questions q
  left join Posts a on a.ParentId = q.QuestionId and a.PostTypeId = 2
  left join Comments c on c.PostId = q.QuestionId
  left join Votes v on v.PostId = q.QuestionId
  group by q.QuestionId, q.Title, q.OwnerUserId, q.OwnerDisplayName, q.OwnerLocation, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
activity_windows as (
  select
    ph.PostId as QuestionId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditDate,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditDate,
    count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13)) as ModActionCount,
    bool_or(ph.PostHistoryTypeId = 50) as HadCommunityBump,
    max(case when ph.PostHistoryTypeId = 10 then nullif(ph.Comment, '') end) as LastCloseReasonId,
    max(ph.CreationDate) as LastHistoryEventAt
  from PostHistory ph
  join recent_questions q on q.QuestionId = ph.PostId
  group by ph.PostId
),
duplicate_graph as (
  select
    q.QuestionId,
    count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as DuplicateOfCount,
    count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as LinkedToCount,
    -- replace array_remove(array_agg(...), null) with array_agg and filter out nulls using array_agg of distinct values and excluding nulls in aggregation expression
    array_agg(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicateTargets
  from recent_questions q
  left join PostLinks pl on pl.PostId = q.QuestionId
  group by q.QuestionId
),
owner_metrics as (
  select
    q.OwnerUserId,
    min(u.CreationDate) as OwnerSince,
    percentile_cont(0.5) within group (order by coalesce(u.Reputation,0)) as OwnerReputationMedian,
    count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
    count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
    count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
    sum(case when b.TagBased = true then 1 else 0 end) as TagBadges
  from recent_questions q
  left join Users u on u.Id = q.OwnerUserId
  left join Badges b on b.UserId = q.OwnerUserId
  group by q.OwnerUserId
),
tag_expansion as (
  select
    q.QuestionId,
    -- replace string_to_array and substring with standard functions: remove leading '<' and trailing '>' then split by '><'
    regexp_split_to_table(
      regexp_replace(q.Tags, '^<|>$', '', 'g'),
      '><'
    ) as TagName
  from recent_questions q
),
hot_tags as (
  select
    te.TagName,
    count(*) as TagUsageCount,
    sum(qs.ViewCount) as TotalViewsWithTag,
    avg(qs.Score) as AvgQScoreWithTag
  from tag_expansion te
  join question_stats qs on qs.QuestionId = te.QuestionId
  group by te.TagName
  having count(*) >= 5
),
tag_ranked as (
  select
    ht.TagName,
    ht.TagUsageCount,
    ht.TotalViewsWithTag,
    ht.AvgQScoreWithTag,
    dense_rank() over (order by ht.TagUsageCount desc, ht.TotalViewsWithTag desc, ht.TagName) as TagRank
  from hot_tags ht
),
accepted_answer_lag as (
  select
    q.Id as QuestionId,
    case when q.AcceptedAnswerId is not null then
      cast(extract(epoch from (a.CreationDate - q.CreationDate)) as bigint)
    else null end as SecondsToAccept
  from Posts q
  left join Posts a on a.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1
    and q.Id in (select QuestionId from recent_questions)
),
question_quality as (
  select
    qs.QuestionId,
    round(
      coalesce(qs.Score,0) * 1.0
      + coalesce(qs.NetVotesFromVotes,0) * 0.7
      + power(coalesce(qs.ViewCount,0), 0.3)
      + coalesce(qs.AnswerCount,0) * 1.25
      + coalesce(qs.MaxAnswerScore,0) * 0.5
      + least(coalesce(aal.SecondsToAccept, 0) / 3600.0, 72) * -0.2
      + case when ag.HadCommunityBump then -1.5 else 0 end
      + case when ag.ModActionCount > 0 then -2.0 else 0 end
    , 3) as QualityScore
  from question_stats qs
  left join activity_windows ag on ag.QuestionId = qs.QuestionId
  left join accepted_answer_lag aal on aal.QuestionId = qs.QuestionId
),
owner_recentness as (
  select
    q.OwnerUserId,
    min(q.CreationDate) as FirstQInWindow,
    max(q.CreationDate) as LastQInWindow,
    count(*) as QuestionsInWindow,
    max(case when q.rn_owner = 1 then q.QuestionId end) as MostRecentQuestionId
  from recent_questions q
  group by q.OwnerUserId
),
owner_activity_score as (
  select
    orm.OwnerUserId,
    round(
      (
        0
      )
      + least(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - orm.FirstQInWindow)) / 86400.0, 365) * -0.01
      + least(orm.QuestionsInWindow, 50) * 0.2
      + coalesce(om.GoldBadges,0) * 0.6
      + coalesce(om.SilverBadges,0) * 0.3
      + coalesce(om.BronzeBadges,0) * 0.1
    , 3) as OwnerActivityScore
  from owner_recentness orm
  left join owner_metrics om on om.OwnerUserId = orm.OwnerUserId
),
final_rank as (
  select
    qs.QuestionId,
    qs.Title,
    qs.OwnerUserId,
    qs.OwnerDisplayName,
    qs.OwnerLocation,
    qs.CreationDate,
    qs.Score,
    qs.ViewCount,
    qs.AnswerCount,
    qs.MaxAnswerScore,
    qs.AvgAnswerScore,
    qs.CommentCount,
    qs.CommentScoreSum,
    qs.FavoriteCountLegacy,
    qs.NetVotesFromVotes,
    qs.MaxBountySeen,
    ag.EditCount,
    ag.FirstEditDate,
    ag.LastEditDate,
    ag.ModActionCount,
    ag.HadCommunityBump,
    ag.LastCloseReasonId,
    dg.DuplicateOfCount,
    dg.LinkedToCount,
    dg.DuplicateTargets,
    qq.QualityScore,
    oas.OwnerActivityScore,
    coalesce(qq.QualityScore,0) + coalesce(oas.OwnerActivityScore,0) as CompositeScore,
    -- replace array_remove(array_agg(...), null) with array_agg of distinct tag names limited by filter (nulls already excluded)
    array_agg(distinct tr.TagName) filter (where tr.TagRank <= 50) as TopTagsOnQuestion,
    count(distinct te.TagName) as DistinctTagCount
  from question_stats qs
  left join activity_windows ag on ag.QuestionId = qs.QuestionId
  left join duplicate_graph dg on dg.QuestionId = qs.QuestionId
  left join question_quality qq on qq.QuestionId = qs.QuestionId
  left join owner_activity_score oas on oas.OwnerUserId = qs.OwnerUserId
  left join tag_expansion te on te.QuestionId = qs.QuestionId
  left join tag_ranked tr on tr.TagName = te.TagName
  group by
    qs.QuestionId, qs.Title, qs.OwnerUserId, qs.OwnerDisplayName, qs.OwnerLocation, qs.CreationDate,
    qs.Score, qs.ViewCount, qs.AnswerCount, qs.MaxAnswerScore, qs.AvgAnswerScore, qs.CommentCount,
    qs.CommentScoreSum, qs.FavoriteCountLegacy, qs.NetVotesFromVotes, qs.MaxBountySeen,
    ag.EditCount, ag.FirstEditDate, ag.LastEditDate, ag.ModActionCount, ag.HadCommunityBump, ag.LastCloseReasonId,
    dg.DuplicateOfCount, dg.LinkedToCount, dg.DuplicateTargets,
    qq.QualityScore, oas.OwnerActivityScore
),
ranked as (
  select
    f.*,
    row_number() over (order by f.CompositeScore desc, f.ViewCount desc, f.Score desc, f.AnswerCount desc, f.QuestionId desc) as rn,
    ntile(10) over (order by f.CompositeScore desc) as decile
  from final_rank f
)
select
  r.QuestionId,
  r.Title,
  r.OwnerUserId,
  coalesce(r.OwnerDisplayName, '(unknown)') as OwnerDisplayName,
  r.OwnerLocation,
  r.CreationDate,
  r.Score,
  r.ViewCount,
  r.AnswerCount,
  r.MaxAnswerScore,
  round(coalesce(r.AvgAnswerScore,0), 2) as AvgAnswerScore,
  r.CommentCount,
  r.CommentScoreSum,
  r.FavoriteCountLegacy,
  r.NetVotesFromVotes,
  r.MaxBountySeen,
  r.EditCount,
  r.FirstEditDate,
  r.LastEditDate,
  r.ModActionCount,
  r.HadCommunityBump,
  r.LastCloseReasonId,
  r.DuplicateOfCount,
  r.LinkedToCount,
  r.DuplicateTargets,
  r.QualityScore,
  r.OwnerActivityScore,
  r.CompositeScore,
  r.TopTagsOnQuestion,
  r.DistinctTagCount,
  r.decile as ScoreDecile,
  case
    when r.CompositeScore is null then 'UNKNOWN'
    when r.CompositeScore >= (select avg(CompositeScore) from final_rank) then 'ABOVE_AVG'
    else 'BELOW_AVG'
  end as CompositeBucket
from ranked r
where r.rn <= 250
union all
select
  r.QuestionId,
  r.Title,
  r.OwnerUserId,
  coalesce(r.OwnerDisplayName, '(unknown)'),
  r.OwnerLocation,
  r.CreationDate,
  r.Score,
  r.ViewCount,
  r.AnswerCount,
  r.MaxAnswerScore,
  round(coalesce(r.AvgAnswerScore,0), 2),
  r.CommentCount,
  r.CommentScoreSum,
  r.FavoriteCountLegacy,
  r.NetVotesFromVotes,
  r.MaxBountySeen,
  r.EditCount,
  r.FirstEditDate,
  r.LastEditDate,
  r.ModActionCount,
  r.HadCommunityBump,
  r.LastCloseReasonId,
  r.DuplicateOfCount,
  r.LinkedToCount,
  r.DuplicateTargets,
  r.QualityScore,
  r.OwnerActivityScore,
  r.CompositeScore,
  r.TopTagsOnQuestion,
  r.DistinctTagCount,
  r.decile,
  'SAMPLE_LOWS' as CompositeBucket
from ranked r
where r.rn > (select count(*) - 10 from ranked)
order by CompositeScore desc, ViewCount desc, Score desc, QuestionId desc;