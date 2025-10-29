-- {"query": "1.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2962} 
with
q as (
  select p.Id as QuestionId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         p.AcceptedAnswerId,
         p.Tags,
         coalesce(nullif(trim(p.Title), ''), '(no title)') as Title,
         date_trunc('month', p.CreationDate) as month_start
  from Posts p
  where p.PostTypeId = 1
),
answers as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswerOwnerId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreated
  from Posts a
  where a.PostTypeId = 2
),
answer_latency as (
  select q.QuestionId,
         min(a.AnswerCreated) as FirstAnswerAt,
         extract(epoch from (min(a.AnswerCreated) - q.CreationDate)) as SecsToFirstAnswer,
         count(*) as AnswerCount
  from q
  left join answers a on a.QuestionId = q.QuestionId
  group by q.QuestionId, q.CreationDate
),
accepted as (
  select q.QuestionId,
         aa.AnswerId as AcceptedAnswerId,
         aa.AnswerOwnerId as AcceptedOwnerId,
         aa.AnswerScore as AcceptedScore,
         aa.AnswerCreated as AcceptedCreated
  from q
  left join answers aa on aa.AnswerId = q.AcceptedAnswerId
),
votes_agg as (
  select v.PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
         sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
         min(v.CreationDate) filter (where v.VoteTypeId in (2,3)) as FirstVoteAt
  from Votes v
  group by v.PostId
),
comment_agg as (
  select c.PostId,
         count(*) as CommentCount,
         max(c.Score) as MaxCommentScore,
         max(length(c.Text)) as MaxCommentLen,
         min(c.CreationDate) as FirstCommentAt
  from Comments c
  group by c.PostId
),
history_flags as (
  select ph.PostId,
         bool_or(ph.PostHistoryTypeId = 10) as WasClosed,
         bool_or(ph.PostHistoryTypeId = 11) as WasReopened,
         bool_or(ph.PostHistoryTypeId = 19) as WasProtected,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as ClosedAt,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as ReopenedAt
  from PostHistory ph
  group by ph.PostId
),
dup_links as (
  select pl.PostId,
         count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
         count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks
  from PostLinks pl
  group by pl.PostId
),
tag_exploded as (
  select q.QuestionId,
         lower(trim(t)) as tag
  from q
  cross join lateral unnest(string_to_array(substring(coalesce(q.Tags,'<>'), 2, greatest(length(coalesce(q.Tags,'<>'))-2,0)), '><')) as t
),
tag_quality as (
  select te.QuestionId,
         count(*) as TagCount,
         sum(case when tg.Count >= 1000 then 1 else 0 end) as PopularTagCount,
         max(tg.Count) as MaxTagGlobalCount
  from tag_exploded te
  left join Tags tg on tg.TagName = te.tag
  group by te.QuestionId
),
user_stats as (
  select u.Id as UserId,
         u.Reputation,
         u.UpVotes,
         u.DownVotes,
         u.Views as ProfileViews,
         date_trunc('month', u.CreationDate) as UserCohort,
         count(b.Id) filter (where b.Class = 1) as GoldBadges,
         count(b.Id) filter (where b.Class = 2) as SilverBadges,
         count(b.Id) filter (where b.Class = 3) as BronzeBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, date_trunc('month', u.CreationDate)
),
activity_window as (
  select q.QuestionId,
         q.month_start,
         row_number() over (partition by q.month_start order by q.Score desc nulls last, q.ViewCount desc nulls last, q.QuestionId) as rn_in_month,
         percentile_cont(0.5) within group (order by q.Score) over (partition by q.month_start) as median_score_month,
         avg(q.ViewCount) over (partition by q.month_start) as avg_views_month
  from q
),
null_sentinels as (
  select q.QuestionId,
         case when q.Title is null or q.Title = '(no title)' then 1 else 0 end as MissingTitle,
         case when q.Tags is null or q.Tags = '' then 1 else 0 end as MissingTags,
         case when q.OwnerUserId is null then 1 else 0 end as AnonymousOwner
  from q
),
quality_bucket as (
  select q.QuestionId,
         case
           when q.Score >= 10 and coalesce(va.UpVotes,0) - coalesce(va.DownVotes,0) >= 15 then 'elite'
           when q.Score >= 5 then 'good'
           when q.Score >= 0 then 'ok'
           else 'poor'
         end as QualityBand
  from q
  left join votes_agg va on va.PostId = q.QuestionId
),
recent_edits as (
  select ph.PostId,
         count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
         max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditAt
  from PostHistory ph
  group by ph.PostId
),
q_enriched as (
  select
    q.QuestionId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.AcceptedAnswerId,
    q.Title,
    q.Tags,
    al.FirstAnswerAt,
    al.SecsToFirstAnswer,
    al.AnswerCount,
    ac.AcceptedOwnerId,
    ac.AcceptedScore,
    va.UpVotes,
    va.DownVotes,
    va.Favorites,
    va.BountyTotal,
    va.FirstVoteAt,
    ca.CommentCount,
    ca.MaxCommentScore,
    ca.MaxCommentLen,
    ca.FirstCommentAt,
    hf.WasClosed,
    hf.WasReopened,
    hf.WasProtected,
    hf.ClosedAt,
    hf.ReopenedAt,
    dl.DuplicateLinks,
    dl.LinkedLinks,
    tq.TagCount,
    tq.PopularTagCount,
    tq.MaxTagGlobalCount,
    aw.rn_in_month,
    aw.median_score_month,
    aw.avg_views_month,
    ns.MissingTitle,
    ns.MissingTags,
    ns.AnonymousOwner,
    qb.QualityBand,
    re.EditCount,
    re.LastEditAt
  from q
  left join answer_latency al on al.QuestionId = q.QuestionId
  left join accepted ac on ac.QuestionId = q.QuestionId
  left join votes_agg va on va.PostId = q.QuestionId
  left join comment_agg ca on ca.PostId = q.QuestionId
  left join history_flags hf on hf.PostId = q.QuestionId
  left join dup_links dl on dl.PostId = q.QuestionId
  left join tag_quality tq on tq.QuestionId = q.QuestionId
  left join activity_window aw on aw.QuestionId = q.QuestionId
  left join null_sentinels ns on ns.QuestionId = q.QuestionId
  left join quality_bucket qb on qb.QuestionId = q.QuestionId
  left join recent_edits re on re.PostId = q.QuestionId
),
owner_join as (
  select qe.*,
         us.Reputation as OwnerReputation,
         us.UpVotes as OwnerUpVotes,
         us.DownVotes as OwnerDownVotes,
         us.ProfileViews as OwnerProfileViews,
         us.GoldBadges,
         us.SilverBadges,
         us.BronzeBadges,
         us.UserCohort
  from q_enriched qe
  left join user_stats us on us.UserId = qe.OwnerUserId
),
rankings as (
  select *,
         dense_rank() over (order by coalesce(UpVotes,0) - coalesce(DownVotes,0) desc, Score desc, ViewCount desc) as GlobalRank,
         dense_rank() over (partition by UserCohort order by coalesce(UpVotes,0) - coalesce(DownVotes,0) desc, Score desc) as CohortRank
  from owner_join
),
filters as (
  select *
  from rankings
  where
    coalesce(TagCount,0) between 1 and 5
    and coalesce(AnswerCount,0) >= 0
    and (WasClosed is distinct from true or ReopenedAt is not null)
    and (MissingTitle = 0)
),
outliers as (
  select f.*,
         case when ViewCount > 3 * avg_views_month then 1 else 0 end as ViewOutlier,
         case when Score > 2 * median_score_month then 1 else 0 end as ScoreOutlier
  from filters f
),
accepted_delta as (
  select o.*,
         case when AcceptedAnswerId is not null and FirstAnswerAt is not null
              then extract(epoch from (coalesce(LastEditAt, FirstAnswerAt) - FirstAnswerAt))
              else null end as SecsEditAfterFirstAnswer,
         case when AcceptedAnswerId is not null and FirstAnswerAt is not null
              then extract(epoch from (FirstAnswerAt - CreationDate))
              else null end as SecsToAcceptedCandidate
  from outliers o
),
stringy as (
  select a.*,
         concat(
           '[', coalesce(nullif(trim(Title), ''),'(no title)'), '] ',
           '(',
           case when TagCount is null or TagCount = 0 then 'no-tags'
                when TagCount = 1 then 'single-tag'
                else 'multi-tag' end,
           ') - ',
           coalesce(qualityband, 'unknown')
         ) as Descriptor,
         coalesce(nullif(regexp_replace(coalesce(Tags,''), '[^a-zA-Z0-9<>-]', '', 'g'),''),'<>') as SanitizedTags
  from accepted_delta a
),
-- simulate heavier workload via set operators and complex predicate
unioned as (
  select * from stringy
  union all
  select * from stringy where ViewOutlier = 1
  union
  select * from stringy where ScoreOutlier = 1
),
final_rank as (
  select u.*,
         row_number() over (order by
           coalesce(UpVotes,0) - coalesce(DownVotes,0) desc,
           coalesce(Favorites,0) desc,
           coalesce(BountyTotal,0) desc,
           Score desc,
           ViewCount desc,
           QuestionId) as HeavyRank
  from unioned u
)
select
  fr.QuestionId,
  fr.OwnerUserId,
  fr.UserCohort,
  fr.CreationDate,
  fr.Title,
  fr.Descriptor,
  fr.SanitizedTags,
  fr.TagCount,
  fr.PopularTagCount,
  fr.MaxTagGlobalCount,
  fr.Score,
  fr.ViewCount,
  fr.UpVotes,
  fr.DownVotes,
  fr.Favorites,
  fr.BountyTotal,
  fr.AnswerCount,
  fr.FirstAnswerAt,
  fr.SecsToFirstAnswer,
  fr.AcceptedAnswerId,
  fr.AcceptedOwnerId,
  fr.AcceptedScore,
  fr.WasClosed,
  fr.WasReopened,
  fr.WasProtected,
  fr.DuplicateLinks,
  fr.LinkedLinks,
  fr.CommentCount,
  fr.MaxCommentScore,
  fr.MaxCommentLen,
  fr.FirstCommentAt,
  fr.EditCount,
  fr.LastEditAt,
  fr.ViewOutlier,
  fr.ScoreOutlier,
  fr.SecsEditAfterFirstAnswer,
  fr.SecsToAcceptedCandidate,
  fr.OwnerReputation,
  fr.OwnerUpVotes,
  fr.OwnerDownVotes,
  fr.OwnerProfileViews,
  fr.GoldBadges,
  fr.SilverBadges,
  fr.BronzeBadges,
  fr.QualityBand,
  fr.GlobalRank,
  fr.CohortRank,
  fr.rn_in_month,
  fr.median_score_month,
  fr.avg_views_month,
  fr.HeavyRank
from final_rank fr
where
  (
    (fr.QualityBand in ('elite','good') and coalesce(fr.Favorites,0) >= 3)
    or
    (fr.ViewOutlier = 1 and fr.Score >= 0)
    or
    (fr.ScoreOutlier = 1 and coalesce(fr.AnswerCount,0) >= 1)
  )
  and not (fr.MissingTags = 1 and fr.DuplicateLinks > 0)
order by fr.HeavyRank
limit 500;