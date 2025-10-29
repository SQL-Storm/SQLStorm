-- {"query": "492.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3410} 
with
q_posts as (
    select p.Id as QuestionId,
           p.CreationDate as QuestionCreationDate,
           p.OwnerUserId as QuestionOwnerId,
           p.Score as QuestionScore,
           p.ViewCount,
           p.Title,
           p.Tags,
           p.AcceptedAnswerId,
           coalesce(p.AnswerCount, 0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
),
a_posts as (
    select a.Id as AnswerId,
           a.ParentId as QuestionId,
           a.OwnerUserId as AnswerOwnerId,
           a.Score as AnswerScore,
           a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
user_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        coalesce(nullif(trim(u.Location), ''), 'Unknown') as LocationNorm,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, u.Views, LocationNorm
),
question_activity as (
    select
        q.QuestionId,
        min(a.AnswerCreationDate) as FirstAnswerDate,
        count(a.AnswerId) as TotalAnswers,
        sum(case when a.AnswerId = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswerPresent,
        max(a.AnswerScore) as MaxAnswerScore,
        avg(a.AnswerScore::numeric) as AvgAnswerScore
    from q_posts q
    left join a_posts a on a.QuestionId = q.QuestionId
    group by q.QuestionId
),
first_interaction as (
    select
        q.QuestionId,
        min(c.CreationDate) as FirstCommentDate,
        min(pl.CreationDate) as FirstLinkDate
    from q_posts q
    left join Comments c on c.PostId = q.QuestionId
    left join PostLinks pl on pl.PostId = q.QuestionId
    group by q.QuestionId
),
question_votes as (
    select
        v.PostId as QuestionId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        count(*) filter (where v.VoteTypeId = 5) as Favorites,
        count(*) filter (where v.VoteTypeId in (8,9)) as BountyEvents,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyAmountTotal
    from Votes v
    join q_posts q on q.QuestionId = v.PostId
    group by v.PostId
),
close_events as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosedDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenedDate,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseCount,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenCount,
        -- extract primary close reason id from Comment if numeric
        mode() within group (order by nullif(regexp_replace(ph.Comment, '[^0-9]', '', 'g'), '')::int) as DominantCloseReasonId
    from PostHistory ph
    join q_posts q on q.QuestionId = ph.PostId
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
duplicate_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinksCount,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount
    from PostLinks pl
    join q_posts q on q.QuestionId = pl.PostId
    group by pl.PostId
),
tag_expansion as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as TagName
    from q_posts q
    where q.Tags is not null and length(q.Tags) > 2
),
tag_metrics as (
    select
        te.QuestionId,
        count(*) as TagCount,
        sum(t.Count) as SumTagGlobalUsage,
        max(t.Count) as MaxTagGlobalUsage,
        min(t.Count) as MinTagGlobalUsage
    from tag_expansion te
    left join Tags t on lower(t.TagName) = lower(te.TagName)
    group by te.QuestionId
),
owner_enrichment as (
    select
        q.QuestionId,
        qu.UserId as OwnerUserId,
        qu.Reputation as OwnerReputation,
        qu.UpVotes as OwnerUpVotes,
        qu.DownVotes as OwnerDownVotes,
        qu.ProfileViews as OwnerProfileViews,
        qu.LocationNorm as OwnerLocation,
        qu.GoldBadges, qu.SilverBadges, qu.BronzeBadges
    from q_posts q
    left join user_stats qu on qu.UserId = q.QuestionOwnerId
),
answerer_diversity as (
    select
        q.QuestionId,
        count(distinct a.AnswerOwnerId) as DistinctAnswerers,
        avg(us.Reputation::numeric) as AvgAnswererReputation,
        min(us.Reputation) as MinAnswererReputation,
        max(us.Reputation) as MaxAnswererReputation
    from q_posts q
    left join a_posts a on a.QuestionId = q.QuestionId
    left join user_stats us on us.UserId = a.AnswerOwnerId
    group by q.QuestionId
),
time_to_events as (
    select
        q.QuestionId,
        extract(epoch from (qa.FirstAnswerDate - q.QuestionCreationDate)) as SecToFirstAnswer,
        extract(epoch from (fi.FirstCommentDate - q.QuestionCreationDate)) as SecToFirstComment,
        extract(epoch from (fi.FirstLinkDate - q.QuestionCreationDate)) as SecToFirstLink,
        extract(epoch from (ce.FirstClosedDate - q.QuestionCreationDate)) as SecToFirstClose
    from q_posts q
    left join question_activity qa on qa.QuestionId = q.QuestionId
    left join first_interaction fi on fi.QuestionId = q.QuestionId
    left join close_events ce on ce.QuestionId = q.QuestionId
),
rolling_views as (
    select
        q.QuestionId,
        q.ViewCount,
        q.QuestionCreationDate,
        sum(q.ViewCount) over (order by q.QuestionCreationDate rows between unbounded preceding and current row) as CumViews,
        avg(q.ViewCount::numeric) over (order by q.QuestionCreationDate rows between 99 preceding and current row) as MovingAvgViews_100
    from q_posts q
),
rankings as (
    select
        q.QuestionId,
        dense_rank() over (order by q.ViewCount desc nulls last) as RankByViews,
        dense_rank() over (order by q.QuestionScore desc nulls last) as RankByScore,
        row_number() over (order by coalesce(q.ViewCount,0) + coalesce(q.QuestionScore,0) desc) as RowNumByEngagement
    from q_posts q
),
question_quality as (
    select
        q.QuestionId,
        q.QuestionScore,
        q.ViewCount,
        qa.TotalAnswers,
        qv.UpVotes,
        qv.DownVotes,
        qv.Favorites,
        qa.AcceptedAnswerPresent,
        (coalesce(q.QuestionScore,0) * 2
         + coalesce(qv.UpVotes,0)
         - coalesce(qv.DownVotes,0) * 2
         + coalesce(qa.TotalAnswers,0)
         + case when qa.AcceptedAnswerPresent > 0 then 5 else 0 end
         + least(coalesce(q.ViewCount,0) / nullif(greatest(qa.TotalAnswers,1),0), 100)
        )::numeric as QualityScore
    from q_posts q
    left join question_activity qa on qa.QuestionId = q.QuestionId
    left join question_votes qv on qv.QuestionId = q.QuestionId
),
accepted_answer_latency as (
    select
        q.QuestionId,
        case
            when q.AcceptedAnswerId is null then null
            else (
                select extract(epoch from (a.AnswerCreationDate - q.QuestionCreationDate))
                from a_posts a
                where a.AnswerId = q.AcceptedAnswerId
            )
        end as SecToAcceptedAnswer
    from q_posts q
),
dup_closed_overlap as (
    select
        q.QuestionId,
        coalesce(dl.DuplicateLinksCount,0) as DuplicateLinksCount,
        coalesce(ce.CloseCount,0) as CloseCount,
        case when coalesce(dl.DuplicateLinksCount,0) > 0 and coalesce(ce.CloseCount,0) > 0 then 1 else 0 end as DupAndClosed
    from q_posts q
    left join duplicate_links dl on dl.QuestionId = q.QuestionId
    left join close_events ce on ce.QuestionId = q.QuestionId
),
tag_coverage as (
    select
        q.QuestionId,
        tm.TagCount,
        coalesce(tm.SumTagGlobalUsage, 0) as SumTagGlobalUsage,
        coalesce(tm.MaxTagGlobalUsage, 0) as MaxTagGlobalUsage,
        coalesce(tm.MinTagGlobalUsage, 0) as MinTagGlobalUsage,
        case when tm.TagCount is null or tm.TagCount = 0 then 'untagged'
             when tm.TagCount = 1 then 'mono'
             when tm.TagCount between 2 and 3 then 'narrow'
             else 'broad' end as TagBreadth
    from q_posts q
    left join tag_metrics tm on tm.QuestionId = q.QuestionId
),
final as (
    select
        q.QuestionId,
        q.Title,
        coalesce(q.Tags, '[]') as TagsRaw,
        oe.OwnerUserId,
        oe.OwnerReputation,
        oe.OwnerLocation,
        oe.GoldBadges, oe.SilverBadges, oe.BronzeBadges,
        qa.TotalAnswers,
        qa.MaxAnswerScore,
        qa.AvgAnswerScore,
        qv.UpVotes, qv.DownVotes, qv.Favorites,
        qv.BountyEvents, qv.BountyAmountTotal,
        ce.FirstClosedDate, ce.LastReopenedDate, ce.CloseCount, ce.ReopenCount, ce.DominantCloseReasonId,
        dl.DuplicateLinksCount, dl.LinkedCount,
        td.TagCount, td.SumTagGlobalUsage, td.MaxTagGlobalUsage, td.MinTagGlobalUsage, td.TagBreadth,
        ad.DistinctAnswerers, ad.AvgAnswererReputation, ad.MinAnswererReputation, ad.MaxAnswererReputation,
        tt.SecToFirstAnswer, tt.SecToFirstComment, tt.SecToFirstLink, tt.SecToFirstClose,
        al.SecToAcceptedAnswer,
        rv.ViewCount, rv.CumViews, rv.MovingAvgViews_100,
        r.RankByViews, r.RankByScore, r.RowNumByEngagement,
        qq.QualityScore,
        q.QuestionCreationDate
    from q_posts q
    left join owner_enrichment oe on oe.QuestionId = q.QuestionId
    left join question_activity qa on qa.QuestionId = q.QuestionId
    left join question_votes qv on qv.QuestionId = q.QuestionId
    left join close_events ce on ce.QuestionId = q.QuestionId
    left join duplicate_links dl on dl.QuestionId = q.QuestionId
    left join tag_coverage td on td.QuestionId = q.QuestionId
    left join answerer_diversity ad on ad.QuestionId = q.QuestionId
    left join time_to_events tt on tt.QuestionId = q.QuestionId
    left join accepted_answer_latency al on al.QuestionId = q.QuestionId
    left join rolling_views rv on rv.QuestionId = q.QuestionId
    left join rankings r on r.QuestionId = q.QuestionId
    left join question_quality qq on qq.QuestionId = q.QuestionId
),
banded as (
    select
        f.*,
        ntile(20) over (order by coalesce(f.QualityScore,0) desc) as QualityVentile,
        case
            when coalesce(f.SecToFirstAnswer, 1e15) < 3600 then 'under_1h'
            when coalesce(f.SecToFirstAnswer, 1e15) < 86400 then 'under_1d'
            when coalesce(f.SecToFirstAnswer, 1e15) < 604800 then 'under_1w'
            else 'slow_or_never'
        end as FirstAnswerBucket
    from final f
),
peer_baselines as (
    select
        b.OwnerLocation,
        b.TagBreadth,
        percentile_cont(0.5) within group (order by coalesce(b.QualityScore,0)) as MedianQualityByPeerGroup,
        avg(coalesce(b.SecToFirstAnswer, 1e6)) as AvgSecToFirstAnswerByPeerGroup
    from banded b
    group by b.OwnerLocation, b.TagBreadth
)
select
    b.QuestionId,
    b.Title,
    b.TagsRaw,
    b.OwnerUserId,
    b.OwnerReputation,
    b.OwnerLocation,
    b.GoldBadges, b.SilverBadges, b.BronzeBadges,
    b.TotalAnswers,
    b.MaxAnswerScore,
    b.AvgAnswerScore,
    b.UpVotes, b.DownVotes, b.Favorites,
    b.BountyEvents, b.BountyAmountTotal,
    b.FirstClosedDate, b.LastReopenedDate, b.CloseCount, b.ReopenCount, b.DominantCloseReasonId,
    b.DuplicateLinksCount, b.LinkedCount,
    b.TagCount, b.SumTagGlobalUsage, b.MaxTagGlobalUsage, b.MinTagGlobalUsage, b.TagBreadth,
    b.DistinctAnswerers, b.AvgAnswererReputation, b.MinAnswererReputation, b.MaxAnswererReputation,
    b.SecToFirstAnswer, b.SecToFirstComment, b.SecToFirstLink, b.SecToFirstClose,
    b.SecToAcceptedAnswer,
    b.ViewCount, b.CumViews, b.MovingAvgViews_100,
    b.RankByViews, b.RankByScore, b.RowNumByEngagement,
    b.QualityScore, b.QualityVentile, b.FirstAnswerBucket,
    pb.MedianQualityByPeerGroup,
    pb.AvgSecToFirstAnswerByPeerGroup,
    b.QuestionCreationDate
from banded b
left join peer_baselines pb
  on pb.OwnerLocation = b.OwnerLocation
 and pb.TagBreadth = b.TagBreadth
where
    coalesce(b.ViewCount,0) > 0
    and (b.CloseCount is null or b.CloseCount <= 3)
    and (b.DominantCloseReasonId is null or b.DominantCloseReasonId not in (101))
order by
    b.QualityVentile desc,
    b.QualityScore desc nulls last,
    b.ViewCount desc nulls last,
    b.QuestionCreationDate desc
limit 500;