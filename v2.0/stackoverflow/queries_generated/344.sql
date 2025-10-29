-- {"query": "344.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2986} 
with params as (
  select
    interval '365 days' as lookback,
    0.75::float as top_fraction,
    10 as min_answers,
    100 as min_views
),
recent_questions as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.OwnerUserId,
    p.Tags,
    coalesce(p.FavoriteCount, 0) as FavoriteCount
  from Posts p
  join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
  cross join params prm
  where p.CreationDate >= now() - prm.lookback
    and coalesce(p.ViewCount, 0) >= prm.min_views
),
answerers as (
  select
    a.ParentId as QuestionId,
    a.Id as AnswerId,
    a.OwnerUserId as AnswerUserId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerDate
  from Posts a
  join PostTypes pt on pt.Id = a.PostTypeId and pt.Name = 'Answer'
),
question_activity as (
  select
    q.QuestionId,
    q.CreationDate,
    q.Score as QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.OwnerUserId,
    q.Tags,
    q.FavoriteCount,
    count(a.AnswerId) filter (where a.AnswerId is not null) as AnswersObserved,
    avg(a.AnswerScore) as AvgAnswerScore,
    max(a.AnswerScore) as MaxAnswerScore,
    min(a.AnswerScore) as MinAnswerScore,
    count(distinct a.AnswerUserId) as DistinctAnswerers,
    max(a.AnswerDate) as LastAnswerDate
  from recent_questions q
  left join answerers a on a.QuestionId = q.QuestionId
  group by q.QuestionId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.OwnerUserId, q.Tags, q.FavoriteCount
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    coalesce(nullif(trim(u.Location), ''), 'Unknown') as LocationNorm,
    case
      when u.WebsiteUrl ilike '%github%' then 'github'
      when u.WebsiteUrl ilike '%gitlab%' then 'gitlab'
      when u.WebsiteUrl ilike '%stackoverflow%' then 'stackoverflow'
      when u.WebsiteUrl is null then 'none'
      else 'other'
    end as SiteBucket
  from Users u
),
questioner as (
  select
    qa.QuestionId,
    us.UserId as QuestionOwnerId,
    us.Reputation as QuestionerRep,
    us.LocationNorm as QuestionerLocation,
    us.SiteBucket as QuestionerSiteBucket,
    us.Views as QuestionerProfileViews,
    us.UpVotes as QuestionerUpVotes,
    us.DownVotes as QuestionerDownVotes
  from question_activity qa
  left join user_stats us on us.UserId = qa.OwnerUserId
),
tag_expanded as (
  select
    qa.QuestionId,
    trim(unnest(string_to_array(substring(qa.Tags from 2 for length(qa.Tags)-2), '><'))) as Tag
  from question_activity qa
  where qa.Tags is not null and qa.Tags like '<%>'
),
tag_meta as (
  select
    te.QuestionId,
    te.Tag,
    t.Count as TagUsageCount,
    coalesce(t.IsModeratorOnly, 0) as IsModeratorOnly,
    coalesce(t.IsRequired, 0) as IsRequired
  from tag_expanded te
  left join Tags t on t.TagName = te.Tag
),
dup_links as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where lt.Name = 'Duplicate') as DupLinkCount,
    count(*) filter (where lt.Name = 'Linked') as LinkedCount,
    max(pl.CreationDate) as LastLinkDate
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId
),
close_events as (
  select
    ph.PostId as QuestionId,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastCloseVoteAt,
    count(*) filter (where ph.PostHistoryTypeId = 11) as Reopens,
    count(*) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenEvents,
    count(*) filter (where ph.PostHistoryTypeId = 19) as Protections
  from PostHistory ph
  group by ph.PostId
),
vote_agg as (
  select
    v.PostId as QuestionId,
    count(*) filter (where vt.Name = 'UpMod') as UpVotes,
    count(*) filter (where vt.Name = 'DownMod') as DownVotes,
    count(*) filter (where vt.Name = 'Favorite') as Favorites,
    count(*) filter (where vt.Name = 'BountyStart') as BountyStarts,
    sum(v.BountyAmount) filter (where vt.Name in ('BountyStart','BountyClose')) as BountyAmountTotal
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
accepted_answer as (
  select
    q.QuestionId,
    p2.Id as AcceptedAnswerId,
    p2.Score as AcceptedAnswerScore,
    p2.OwnerUserId as AcceptedAnswerUserId
  from question_activity q
  left join Posts p on p.Id = q.QuestionId
  left join Posts p2 on p2.Id = p.AcceptedAnswerId
),
answerer_engagement as (
  select
    a.QuestionId,
    count(*) as TotalAnswers,
    sum(case when us.Reputation >= 10000 then 1 else 0 end) as HighRepAnswers,
    avg(coalesce(us.Reputation, 0)) as AvgAnswererRep,
    sum(case when us.SiteBucket = 'github' then 1 else 0 end) as GithubSiteAnswers
  from answerers a
  left join user_stats us on us.UserId = a.AnswerUserId
  group by a.QuestionId
),
ranked_questions as (
  select
    qa.*,
    coalesce(va.UpVotes, 0) as QUpVotes,
    coalesce(va.DownVotes, 0) as QDownVotes,
    coalesce(va.Favorites, 0) as QFavoritesVotes,
    coalesce(va.BountyStarts, 0) as QBountyStarts,
    coalesce(va.BountyAmountTotal, 0) as QBountyAmount,
    coalesce(ce.CloseVotes, 0) as CloseVotes,
    ce.LastCloseVoteAt,
    coalesce(ce.Reopens, 0) as Reopens,
    coalesce(ce.CloseReopenEvents, 0) as CloseReopenEvents,
    coalesce(ce.Protections, 0) as Protections,
    coalesce(dl.DupLinkCount, 0) as DupLinkCount,
    coalesce(dl.LinkedCount, 0) as LinkedCount,
    dl.LastLinkDate,
    aa.AcceptedAnswerId,
    aa.AcceptedAnswerScore,
    aa.AcceptedAnswerUserId,
    ae.TotalAnswers,
    ae.HighRepAnswers,
    ae.AvgAnswererRep,
    ae.GithubSiteAnswers,
    qn.QuestionerRep,
    qn.QuestionerLocation,
    qn.QuestionerSiteBucket,
    qn.QuestionerProfileViews,
    qn.QuestionerUpVotes,
    qn.QuestionerDownVotes,
    row_number() over (order by qa.ViewCount desc, qa.Score desc, coalesce(va.UpVotes,0) desc) as PopularityRank
  from question_activity qa
  left join vote_agg va on va.QuestionId = qa.QuestionId
  left join close_events ce on ce.QuestionId = qa.QuestionId
  left join dup_links dl on dl.QuestionId = qa.QuestionId
  left join accepted_answer aa on aa.QuestionId = qa.QuestionId
  left join answerer_engagement ae on ae.QuestionId = qa.QuestionId
  left join questioner qn on qn.QuestionId = qa.QuestionId
),
tag_rollups as (
  select
    tm.QuestionId,
    count(*) as TagCount,
    sum(tm.TagUsageCount) as SumTagUsage,
    max(tm.TagUsageCount) as MaxTagUsage,
    count(*) filter (where tm.IsModeratorOnly = 1) as ModeratorOnlyTags,
    count(*) filter (where tm.IsRequired = 1) as RequiredTags,
    string_agg(tm.Tag order by tm.Tag, ',') as TagList
  from tag_meta tm
  group by tm.QuestionId
),
quality_scores as (
  select
    rq.QuestionId,
    rq.PopularityRank,
    rq.QuestionScore,
    rq.ViewCount,
    rq.AnswerCount,
    rq.AnswersObserved,
    rq.QUpVotes,
    rq.QDownVotes,
    rq.QFavoritesVotes,
    rq.QBountyStarts,
    rq.QBountyAmount,
    rq.CloseVotes,
    rq.Reopens,
    rq.DupLinkCount,
    rq.LinkedCount,
    rq.AcceptedAnswerId,
    rq.AcceptedAnswerScore,
    rq.HighRepAnswers,
    rq.AvgAnswererRep,
    rq.GithubSiteAnswers,
    rq.QuestionerRep,
    rq.QuestionerUpVotes,
    rq.QuestionerDownVotes,
    tr.TagCount,
    tr.SumTagUsage,
    tr.MaxTagUsage,
    tr.ModeratorOnlyTags,
    tr.RequiredTags,
    tr.TagList,
    -- composite quality score emphasizing engagement and resilience
    (
      coalesce(rq.QUpVotes,0)*2
      - coalesce(rq.QDownVotes,0)
      + coalesce(rq.QFavoritesVotes,0)
      + greatest(coalesce(rq.AcceptedAnswerScore,0),0)
      + least(coalesce(rq.ViewCount,0)/100, 50)
      + coalesce(rq.HighRepAnswers,0)*3
      + case when coalesce(rq.CloseVotes,0) > 0 then -10 else 0 end
      + case when coalesce(rq.Reopens,0) > 0 then 5 else 0 end
      + case when coalesce(tr.ModeratorOnlyTags,0) > 0 then -5 else 0 end
      + case when coalesce(tr.RequiredTags,0) > 0 then 2 else 0 end
    )::numeric as QualityScore,
    -- normalized entropy-like tag diversity proxy
    case
      when tr.TagCount is null or tr.TagCount = 0 then null
      else round(ln(tr.TagCount + 1)::numeric, 3)
    end as TagDiversity,
    -- anomaly score: high views with low score or many links/dups
    (
      case
        when coalesce(rq.ViewCount,0) >= 10000 and coalesce(rq.QuestionScore,0) <= 0 then 1
        else 0
      end
      + case when coalesce(rq.DupLinkCount,0) >= 2 then 1 else 0 end
      + case when coalesce(rq.LinkedCount,0) >= 5 then 1 else 0 end
    ) as AnomalyFlags
  from ranked_questions rq
  left join tag_rollups tr on tr.QuestionId = rq.QuestionId
),
percentiles as (
  select
    qs.*,
    ntile(4) over (order by QualityScore desc nulls last) as QualityQuartile,
    percent_rank() over (order by QualityScore) as QualityPercentRank,
    cume_dist() over (order by ViewCount desc nulls last) as ViewCumeDist
  from quality_scores qs
),
top_filtered as (
  select
    p.*,
    dense_rank() over (order by p.QualityScore desc nulls last) as DenseRankQuality,
    row_number() over (partition by coalesce(p.TagList,'') order by p.QualityScore desc, p.ViewCount desc) as RowPerTagList
  from percentiles p
  cross join params prm
  where coalesce(p.AnswersObserved,0) >= prm.min_answers
)
select
  tf.QuestionId,
  tf.PopularityRank,
  tf.QualityQuartile,
  round(tf.QualityPercentRank::numeric, 4) as QualityPercentRank,
  round(tf.ViewCumeDist::numeric, 4) as ViewCumeDist,
  tf.QualityScore,
  tf.TagDiversity,
  tf.AnomalyFlags,
  tf.ViewCount,
  tf.QuestionScore,
  tf.AnswerCount,
  tf.AnswersObserved,
  tf.QUpVotes,
  tf.QDownVotes,
  tf.QFavoritesVotes,
  tf.QBountyStarts,
  tf.QBountyAmount,
  tf.CloseVotes,
  tf.Reopens,
  tf.DupLinkCount,
  tf.LinkedCount,
  tf.AcceptedAnswerId,
  tf.AcceptedAnswerScore,
  tf.HighRepAnswers,
  tf.AvgAnswererRep,
  tf.GithubSiteAnswers,
  tf.QuestionerRep,
  tf.QuestionerUpVotes,
  tf.QuestionerDownVotes,
  tf.TagCount,
  tf.SumTagUsage,
  tf.MaxTagUsage,
  tf.ModeratorOnlyTags,
  tf.RequiredTags,
  tf.TagList,
  tf.DenseRankQuality,
  tf.RowPerTagList
from top_filtered tf
qualify DenseRankQuality <= (select ceil(count(*) * (select top_fraction from params)) from top_filtered)
order by tf.QualityScore desc nulls last, tf.ViewCount desc, tf.QuestionId asc;