-- {"query": "40.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3036} 
with recent_activity as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        coalesce(nullif(trim(p.Title), ''), '[no title]') as NormalizedTitle,
        lower(coalesce(p.Tags, '')) as TagsRaw,
        case when p.PostTypeId = 1 then p.AcceptedAnswerId end as AcceptedAnswerId,
        case when p.PostTypeId = 2 then p.ParentId end as ParentId,
        row_number() over (partition by p.OwnerUserId order by p.LastActivityDate desc nulls last, p.Id desc) as rn_owner_activity
    from Posts p
    where p.CreationDate >= (now() - interval '5 years')
),
owner_stats as (
    select 
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        u.CreationDate as UserCreated,
        coalesce(nullif(trim(u.Location), ''), '[unknown]') as LocationNorm,
        sum(case when ra.PostTypeId = 1 then 1 else 0 end) as QuestionsCount5y,
        sum(case when ra.PostTypeId = 2 then 1 else 0 end) as AnswersCount5y,
        count(*) as PostsCount5y,
        max(ra.LastActivityDate) as LastActivityAny,
        avg(nullif(ra.Score,0)) filter (where ra.Score is not null) as AvgNonZeroScore5y
    from Users u
    left join recent_activity ra
      on ra.OwnerUserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate, LocationNorm
),
accepted_answers as (
    select 
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        a.Score as AcceptedScore,
        a.OwnerUserId as AcceptedOwnerId,
        a.CreationDate as AcceptedCreation
    from Posts q
    join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
),
tag_explode as (
    select
        ra.PostId,
        unnest(string_to_array(substring(ra.TagsRaw, 2, greatest(length(ra.TagsRaw)-2,0)), '><')) as tag
    from recent_activity ra
    where ra.PostTypeId = 1 and ra.TagsRaw like '<%>'
),
tag_popularity as (
    select
        te.tag,
        count(*) as TagUsageCnt5y,
        count(distinct te.PostId) as DistinctPosts5y
    from tag_explode te
    group by te.tag
),
vote_rollup as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesCnt,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesCnt,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
        min(v.CreationDate) as FirstVoteAt,
        max(v.CreationDate) as LastVoteAt
    from Votes v
    where v.CreationDate >= (now() - interval '5 years')
    group by v.PostId
),
comment_activity as (
    select
        c.PostId,
        count(*) as CommentCnt5y,
        max(c.CreationDate) as LastCommentAt,
        sum(case when c.Score > 0 then 1 else 0 end) as PosCommentCnt
    from Comments c
    where c.CreationDate >= (now() - interval '5 years')
    group by c.PostId
),
closed_reasons as (
    select
        ph.PostId,
        min(ph.CreationDate) as FirstClosedAt,
        max(ph.CreationDate) as LastClosedAt,
        max(case when ph.PostHistoryTypeId = 10 then try_cast(nullif(ph.Comment,'') as int) end) as LastCloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
dup_links as (
    select
        pl.PostId as DuplicateOfPostId,
        pl.RelatedPostId as CanonicalPostId,
        min(pl.CreationDate) as FirstDupLinkAt,
        count(*) as DupLinkCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId, pl.RelatedPostId
),
post_enriched as (
    select
        ra.PostId,
        ra.PostTypeId,
        ra.OwnerUserId,
        ra.Score,
        ra.ViewCount,
        ra.CreationDate,
        ra.LastActivityDate,
        ra.NormalizedTitle,
        ra.AcceptedAnswerId,
        ra.ParentId,
        ors.Reputation as OwnerReputation,
        ors.PostsCount5y as OwnerPosts5y,
        ors.QuestionsCount5y as OwnerQuestions5y,
        ors.AnswersCount5y as OwnerAnswers5y,
        vr.UpVotesCnt,
        vr.DownVotesCnt,
        vr.BountyStarted,
        vr.BountyAwarded,
        ca.CommentCnt5y,
        ca.LastCommentAt,
        cr.FirstClosedAt,
        cr.LastClosedAt,
        cr.LastCloseReasonId,
        dl.CanonicalPostId,
        dl.FirstDupLinkAt,
        aa.AcceptedScore,
        aa.AcceptedOwnerId,
        aa.AcceptedCreation
    from recent_activity ra
    left join owner_stats ors on ors.UserId = ra.OwnerUserId
    left join vote_rollup vr on vr.PostId = ra.PostId
    left join comment_activity ca on ca.PostId = ra.PostId
    left join closed_reasons cr on cr.PostId = ra.PostId
    left join dup_links dl on dl.DuplicateOfPostId = ra.PostId
    left join accepted_answers aa on aa.QuestionId = ra.PostId
),
rankings as (
    select
        pe.*,
        coalesce(pe.UpVotesCnt,0) - coalesce(pe.DownVotesCnt,0) as NetVotes5y,
        case 
            when pe.ViewCount is null or pe.ViewCount = 0 then null
            else (pe.Score::numeric / nullif(pe.ViewCount,0)) 
        end as ScorePerView,
        dense_rank() over (order by coalesce(pe.Score, -2147483648) desc, coalesce(pe.ViewCount, -2147483648) desc) as RankByScoreView,
        row_number() over (partition by pe.PostTypeId order by coalesce(pe.Score, -2147483648) desc, coalesce(pe.ViewCount, -2147483648) desc) as RowByTypeScoreView,
        ntile(10) over (order by coalesce(pe.Score,0) desc) as DecileByScore
    from post_enriched pe
),
tag_agg_per_post as (
    select
        te.PostId,
        array_agg(te.tag order by te.tag) as TagsArray,
        string_agg(te.tag, ',' order by te.tag) as TagsCsv,
        sum(tp.TagUsageCnt5y) as SumTagPopularity5y,
        max(tp.TagUsageCnt5y) as MaxTagPopularity5y
    from tag_explode te
    left join tag_popularity tp on tp.tag = te.tag
    group by te.PostId
),
post_final as (
    select
        r.PostId,
        r.PostTypeId,
        r.OwnerUserId,
        r.Score,
        r.ViewCount,
        r.CreationDate,
        r.LastActivityDate,
        r.NormalizedTitle,
        r.AcceptedAnswerId,
        r.ParentId,
        r.OwnerReputation,
        r.OwnerPosts5y,
        r.OwnerQuestions5y,
        r.OwnerAnswers5y,
        r.UpVotesCnt,
        r.DownVotesCnt,
        r.BountyStarted,
        r.BountyAwarded,
        r.CommentCnt5y,
        r.LastCommentAt,
        r.FirstClosedAt,
        r.LastClosedAt,
        r.LastCloseReasonId,
        r.CanonicalPostId,
        r.FirstDupLinkAt,
        r.AcceptedScore,
        r.AcceptedOwnerId,
        r.AcceptedCreation,
        r.NetVotes5y,
        r.ScorePerView,
        r.RankByScoreView,
        r.RowByTypeScoreView,
        r.DecileByScore,
        coalesce(ta.TagsArray, array[]::varchar[]) as TagsArray,
        coalesce(ta.TagsCsv, '') as TagsCsv,
        coalesce(ta.SumTagPopularity5y, 0) as SumTagPopularity5y,
        coalesce(ta.MaxTagPopularity5y, 0) as MaxTagPopularity5y
    from rankings r
    left join tag_agg_per_post ta on ta.PostId = r.PostId
),
user_quartiles as (
    select
        os.UserId,
        ntile(4) over (order by os.Reputation desc) as RepQuartile,
        ntile(4) over (order by os.PostsCount5y desc nulls last) as ActivityQuartile
    from owner_stats os
),
question_quality as (
    select
        pf.PostId,
        case 
            when pf.PostTypeId = 1 then
                (coalesce(pf.Score,0) * 3)
                + (coalesce(pf.NetVotes5y,0) * 2)
                + (case when pf.AcceptedAnswerId is not null then 50 else 0 end)
                + least(coalesce(pf.ViewCount,0)/100, 200)
                - (case when pf.LastCloseReasonId is not null then 100 else 0 end)
                + least(coalesce(pf.CommentCnt5y,0), 25)
            else null
        end as QuestionQualityScore
    from post_final pf
),
answer_quality as (
    select
        pf.PostId,
        case 
            when pf.PostTypeId = 2 then
                (coalesce(pf.Score,0) * 4)
                + (coalesce(pf.NetVotes5y,0) * 3)
                + (least(coalesce(pf.BountyAwarded,0), 500))
                + (case when exists (
                        select 1 
                        from Posts q 
                        where q.Id = pf.ParentId 
                          and q.AcceptedAnswerId = pf.PostId
                    ) then 75 else 0 end)
                + least(coalesce(pf.CommentCnt5y,0), 15)
            else null
        end as AnswerQualityScore
    from post_final pf
),
final_scores as (
    select
        pf.*,
        qq.QuestionQualityScore,
        aq.AnswerQualityScore,
        coalesce(qq.QuestionQualityScore, aq.AnswerQualityScore, 0) as UnifiedQualityScore
    from post_final pf
    left join question_quality qq on qq.PostId = pf.PostId
    left join answer_quality aq on aq.PostId = pf.PostId
)
select
    fs.PostId,
    fs.PostTypeId,
    fs.OwnerUserId,
    u.DisplayName as OwnerDisplayName,
    uq.RepQuartile,
    uq.ActivityQuartile,
    fs.NormalizedTitle,
    fs.TagsCsv,
    fs.Score,
    fs.ViewCount,
    fs.NetVotes5y,
    fs.ScorePerView,
    fs.DecileByScore,
    fs.UnifiedQualityScore,
    fs.RankByScoreView,
    fs.RowByTypeScoreView,
    fs.OwnerReputation,
    fs.CommentCnt5y,
    fs.BountyAwarded,
    fs.FirstClosedAt,
    crt.Name as LastCloseReasonName,
    coalesce(tpop.TopTag, '[none]') as TopTagByGlobalPopularity,
    coalesce(tpop.TopTagUsage, 0) as TopTagUsageCount,
    fs.CreationDate,
    fs.LastActivityDate,
    greatest(fs.LastActivityDate, fs.LastCommentAt, fs.FirstDupLinkAt, fs.LastClosedAt) as LastSignalAt
from final_scores fs
left join Users u on u.Id = fs.OwnerUserId
left join user_quartiles uq on uq.UserId = fs.OwnerUserId
left join CloseReasonTypes crt on crt.Id = fs.LastCloseReasonId
left join lateral (
    select te.tag as TopTag, tp.TagUsageCnt5y as TopTagUsage
    from tag_explode te
    join tag_popularity tp on tp.tag = te.tag
    where te.PostId = fs.PostId
    order by tp.TagUsageCnt5y desc, te.tag asc
    limit 1
) tpop on true
where
    -- Filter to "interesting" posts with various predicate shapes
    (
        (fs.PostTypeId = 1 and coalesce(fs.Score,0) >= 5 and fs.ViewCount >= 500)
        or
        (fs.PostTypeId = 2 and coalesce(fs.Score,0) >= 3 and coalesce(fs.BountyAwarded,0) > 0)
        or
        (fs.NetVotes5y >= 10 and fs.DecileByScore <= 3)
        or
        (fs.UnifiedQualityScore >= 150)
    )
    and not (
        fs.PostTypeId = 1 
        and fs.LastCloseReasonId is not null 
        and fs.NetVotes5y < 0
    )
    and (
        fs.OwnerReputation is null 
        or fs.OwnerReputation > 50 
        or (fs.OwnerReputation between 1 and 50 and fs.UnifiedQualityScore > 200)
    )
order by
    fs.UnifiedQualityScore desc nulls last,
    fs.NetVotes5y desc nulls last,
    fs.ViewCount desc nulls last,
    fs.PostId desc
limit 500;