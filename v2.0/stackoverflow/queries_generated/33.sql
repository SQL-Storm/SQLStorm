-- {"query": "33.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3547} 
with recent_activity as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CreationDate,
        p.LastActivityDate,
        coalesce(nullif(trim(p.Title), ''), '(no title)') as SafeTitle,
        string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><') as TagArray
    from Posts p
    where p.CreationDate >= (select date_trunc('month', max(CreationDate)) - interval '6 months' from Posts)
),
user_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        u.CreationDate as UserCreationDate,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate
),
votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesOnPost,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesOnPost,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoritesOnPost,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
        count(*) as TotalVotes
    from Votes v
    group by v.PostId
),
comments_agg as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.Score) as MaxCommentScore,
        min(c.Score) as MinCommentScore,
        avg(c.Score) as AvgCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
postlinks_agg as (
    select
        pl.PostId,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateOfCount,
        count(*) as TotalLinks
    from PostLinks pl
    group by pl.PostId
),
history_flags as (
    select
        ph.PostId,
        bool_or(ph.PostHistoryTypeId = 10) as WasClosed,
        bool_or(ph.PostHistoryTypeId = 11) as WasReopened,
        bool_or(ph.PostHistoryTypeId = 12) as WasDeleted,
        bool_or(ph.PostHistoryTypeId = 13) as WasUndeleted,
        bool_or(ph.PostHistoryTypeId = 19) as WasProtected,
        bool_or(ph.PostHistoryTypeId = 50) as CommunityBump,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,11,12,13,19,50)) as LastModerationEvent
    from PostHistory ph
    group by ph.PostId
),
tag_expansion as (
    select
        r.PostId,
        lower(trim(tn)) as tagname
    from recent_activity r
    cross join lateral unnest(coalesce(r.TagArray, array[]::varchar[])) as tn
),
tag_rank as (
    select
        te.PostId,
        te.tagname,
        t.Count as TagGlobalCount,
        row_number() over (partition by te.PostId order by coalesce(t.Count,0) desc nulls last, te.tagname) as tag_rank_by_popularity
    from tag_expansion te
    left join Tags t on lower(t.TagName) = te.tagname
),
post_type_name as (
    select Id, Name from PostTypes
),
dup_chain as (
    select
        r.PostId,
        pl.RelatedPostId as TargetId,
        1 as Depth
    from recent_activity r
    join PostLinks pl on pl.PostId = r.PostId and pl.LinkTypeId = 3
    union all
    select
        d.PostId,
        pl2.RelatedPostId,
        d.Depth + 1
    from dup_chain d
    join PostLinks pl2 on pl2.PostId = d.TargetId and pl2.LinkTypeId = 3
    where d.Depth < 3
),
dup_terminal as (
    select
        PostId,
        min(TargetId) keep (dense_rank last order by Depth) as LikelyCanonicalId
    from (
        select
            PostId,
            TargetId,
            Depth,
            row_number() over (partition by PostId order by Depth desc, TargetId) as rn
        from dup_chain
    ) x
    where rn = 1
    group by PostId
),
answers_stats as (
    select
        q.Id as QuestionId,
        count(a.Id) as AnswersCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAccepted
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
score_trend as (
    select
        p.Id as PostId,
        p.CreationDate::date as Day,
        sum(coalesce(v2.VoteDelta,0)) over (partition by p.Id order by p.CreationDate::date rows between unbounded preceding and current row) as CumScore
    from Posts p
    left join (
        select
            v.PostId,
            v.CreationDate::date as vday,
            sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as VoteDelta
        from Votes v
        group by v.PostId, v.CreationDate::date
    ) v2
      on v2.PostId = p.Id and v2.vday = p.CreationDate::date
),
activity_window as (
    select
        r.PostId,
        r.OwnerUserId,
        r.Score,
        r.ViewCount,
        r.AnswerCount,
        r.CreationDate,
        r.LastActivityDate,
        dense_rank() over (order by coalesce(r.LastActivityDate, r.CreationDate) desc, r.Score desc, r.PostId desc) as recency_rank,
        row_number() over (partition by r.OwnerUserId order by coalesce(r.LastActivityDate, r.CreationDate) desc, r.Score desc) as user_recent_order
    from recent_activity r
),
user_quality as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.UpVotes,
        ua.DownVotes,
        ua.ProfileViews,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.LastBadgeDate,
        case
            when ua.Reputation >= 20000 then 'Legend'
            when ua.Reputation >= 10000 then 'Expert'
            when ua.Reputation >= 2000 then 'Contributor'
            when ua.Reputation >= 200 then 'Member'
            else 'New'
        end as UserTier,
        (ua.UpVotes - ua.DownVotes) as NetVotesGiven,
        coalesce(nullif(ua.DisplayName, ''), '(user ' || ua.UserId || ')') as SafeDisplayName
    from user_activity ua
),
final_posts as (
    select
        aw.PostId,
        aw.OwnerUserId,
        aw.Score,
        aw.ViewCount,
        aw.AnswerCount,
        aw.CreationDate,
        aw.LastActivityDate,
        aw.recency_rank,
        aw.user_recent_order,
        pt.Name as PostTypeName,
        coalesce(ra.SafeTitle, '(untitled)') as Title,
        va.UpVotesOnPost,
        va.DownVotesOnPost,
        va.FavoritesOnPost,
        va.BountyTotal,
        va.TotalVotes,
        ca.CommentCount,
        ca.MaxCommentScore,
        ca.MinCommentScore,
        ca.AvgCommentScore,
        ca.LastCommentDate,
        pla.LinkedCount,
        pla.DuplicateOfCount,
        pla.TotalLinks,
        hf.WasClosed,
        hf.WasReopened,
        hf.WasDeleted,
        hf.WasUndeleted,
        hf.WasProtected,
        hf.CommunityBump,
        hf.LastModerationEvent,
        dt.LikelyCanonicalId,
        ast.AnswersCount as ComputedAnswerCount,
        ast.MaxAnswerScore,
        ast.AvgAnswerScore
    from activity_window aw
    join recent_activity ra on ra.PostId = aw.PostId
    left join votes_agg va on va.PostId = aw.PostId
    left join comments_agg ca on ca.PostId = aw.PostId
    left join postlinks_agg pla on pla.PostId = aw.PostId
    left join history_flags hf on hf.PostId = aw.PostId
    left join dup_terminal dt on dt.PostId = aw.PostId
    left join answers_stats ast on ast.QuestionId = aw.PostId
    left join post_type_name pt on pt.Id = (select PostTypeId from Posts p where p.Id = aw.PostId)
),
tag_pivot as (
    select
        tr.PostId,
        max(case when tr.tag_rank_by_popularity = 1 then tr.tagname end) as TopTag1,
        max(case when tr.tag_rank_by_popularity = 2 then tr.tagname end) as TopTag2,
        max(case when tr.tag_rank_by_popularity = 3 then tr.tagname end) as TopTag3
    from tag_rank tr
    where tr.tag_rank_by_popularity <= 3
    group by tr.PostId
),
score_bucket as (
    select
        fp.PostId,
        case
            when fp.Score >= 1000 then 'S4'
            when fp.Score >= 100 then 'S3'
            when fp.Score >= 10 then 'S2'
            when fp.Score >= 1 then 'S1'
            when fp.Score is null then 'SN'
            else 'S0'
        end as ScoreBucket
    from final_posts fp
),
view_efficiency as (
    select
        fp.PostId,
        case
            when coalesce(fp.ViewCount,0) = 0 then null
            else round((coalesce(fp.UpVotesOnPost,0)::numeric - coalesce(fp.DownVotesOnPost,0)::numeric) / nullif(fp.ViewCount::numeric,0), 6)
        end as VotePerView,
        case
            when coalesce(fp.AnswerCount,0) = 0 then null
            else round(fp.ViewCount::numeric / nullif(fp.AnswerCount::numeric,0), 2)
        end as ViewsPerAnswer
    from final_posts fp
),
ranked as (
    select
        fp.*,
        tp.TopTag1, tp.TopTag2, tp.TopTag3,
        sb.ScoreBucket,
        ve.VotePerView, ve.ViewsPerAnswer,
        uq.UserTier, uq.SafeDisplayName,
        row_number() over (
            order by
                coalesce(fp.BountyTotal,0) desc,
                coalesce(fp.UpVotesOnPost - fp.DownVotesOnPost, fp.Score, 0) desc,
                coalesce(fp.ViewCount,0) desc,
                fp.PostId desc
        ) as GlobalRank
    from final_posts fp
    left join tag_pivot tp on tp.PostId = fp.PostId
    left join score_bucket sb on sb.PostId = fp.PostId
    left join view_efficiency ve on ve.PostId = fp.PostId
    left join user_quality uq on uq.UserId = fp.OwnerUserId
),
user_rollups as (
    select
        r.OwnerUserId,
        count(*) as UserPostCount,
        sum(coalesce(r.UpVotesOnPost,0)) as UserTotalUpVotesOnPosts,
        sum(coalesce(r.DownVotesOnPost,0)) as UserTotalDownVotesOnPosts,
        sum(coalesce(r.FavoritesOnPost,0)) as UserTotalFavorites,
        sum(coalesce(r.BountyTotal,0)) as UserTotalBounty,
        avg(coalesce(r.AvgAnswerScore,0)) as UserAvgAnswerScoreAcrossQs,
        max(r.Score) as UserMaxPostScore,
        min(r.Score) as UserMinPostScore
    from ranked r
    group by r.OwnerUserId
),
null_proof as (
    select
        r.*,
        coalesce(r.CommentCount, 0) as NP_CommentCount,
        coalesce(r.TotalLinks, 0) as NP_TotalLinks,
        coalesce(r.UpVotesOnPost, 0) as NP_UpVotesOnPost,
        coalesce(r.DownVotesOnPost, 0) as NP_DownVotesOnPost
    from ranked r
)
select
    r.GlobalRank,
    r.PostId,
    r.PostTypeName,
    r.Title,
    r.TopTag1, r.TopTag2, r.TopTag3,
    r.Score, r.ScoreBucket,
    r.ViewCount,
    r.AnswerCount,
    r.UpVotesOnPost, r.DownVotesOnPost, r.FavoritesOnPost, r.BountyTotal,
    r.TotalVotes,
    r.CommentCount, r.MaxCommentScore, r.MinCommentScore, r.AvgCommentScore,
    r.LinkedCount, r.DuplicateOfCount, r.TotalLinks,
    r.WasClosed, r.WasReopened, r.WasDeleted, r.WasUndeleted, r.WasProtected, r.CommunityBump,
    r.LikelyCanonicalId,
    r.ComputedAnswerCount, r.MaxAnswerScore, r.AvgAnswerScore,
    r.VotePerView, r.ViewsPerAnswer,
    r.OwnerUserId,
    r.SafeDisplayName,
    r.UserTier,
    ur.UserPostCount, ur.UserTotalUpVotesOnPosts, ur.UserTotalDownVotesOnPosts, ur.UserTotalFavorites, ur.UserTotalBounty,
    ur.UserAvgAnswerScoreAcrossQs,
    ur.UserMaxPostScore, ur.UserMinPostScore,
    r.CreationDate, r.LastActivityDate,
    case
        when r.WasClosed and not r.WasReopened then 'Closed'
        when r.WasDeleted and not r.WasUndeleted then 'Deleted'
        when r.WasProtected then 'Protected'
        when r.CommunityBump then 'Bumped'
        else 'Normal'
    end as CurrentModerationState,
    case when r.TopTag1 is null then 'untagged' else r.TopTag1 end ||
    coalesce('|' || r.TopTag2, '') ||
    coalesce('|' || r.TopTag3, '') as TagSignature,
    case
        when r.ViewCount is null or r.ViewCount = 0 then null
        when r.UpVotesOnPost is null then null
        else round(100.0 * (r.UpVotesOnPost::numeric / r.ViewCount::numeric), 4)
    end as UpvoteRatePct
from null_proof r
left join user_rollups ur on ur.OwnerUserId = r.OwnerUserId
where (
        r.ScoreBucket in ('S3','S4')
        or (r.BountyTotal is not null and r.BountyTotal > 0)
        or (r.WasClosed is true and r.WasReopened is not true)
        or (r.TotalLinks is not null and r.TotalLinks > 5)
    )
and (
        r.TopTag1 is null
        or r.TopTag1 not like any (array['meta%','discussion%'])
    )
and (
        r.SafeDisplayName is not null
        or r.OwnerUserId is null
    )
order by r.GlobalRank
limit 500;