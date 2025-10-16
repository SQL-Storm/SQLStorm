-- {"query": "1465.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1443} 
with recursive CTEUserReputation AS (
    select
        u.Id,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (partition by u.Location order by u.Reputation desc nulls last) as LocationRank,
        count(*) over (partition by u.Location) as LocationCount
    from
        Users u
    where
        u.Reputation is not null
), CTEPostStats AS (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        length(p.Body) as BodyLength,
        p.AnswerCount,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        array_to_string(regexp_matches(coalesce(p.Tags,''),'{?<tag>[^<>]+}','g'), ',') as SimpleTags
    from Posts p
    where
        p.PostTypeId in (1, 2)
), CTEAnswerRank AS (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        rank() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate) as ScoreRank
    from
        Posts a
    where
        a.PostTypeId = 2
), CTEQuestionWithAcceptedAnswer AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        ar.ScoreRank
    from
        Posts q
        left join Posts a on q.AcceptedAnswerId = a.Id
        left join CTEAnswerRank ar on ar.AnswerId = a.Id
    where q.PostTypeId = 1
), CTECommentsStats AS (
    select
        c.PostId,
        count(c.Id) as CommentCountTotal,
        sum(c.Score) as CommentScoreSum,
        count(filter(x => x.UserId is null)) over () as AnonymousCommentUserCount
    from
        Comments c
    group by
        c.PostId
), CTEPostLikesDislikesRatio AS (
    select
        p.Id,
        count(vld.RepVal) filter(where v.VoteTypeId = 2) as UpVotes,
        count(vld.RepVal) filter(where v.VoteTypeId = 3) as DownVotes,
        case
            when count(vld.RepVal) filter(where v.VoteTypeId = 3) = 0 then null
            else 1.0 * count(vld.RepVal) filter(where v.VoteTypeId = 2) / count(vld.RepVal) filter(where v.VoteTypeId = 3)
        end as LikeDislikeRatio
    from
        Posts p
        left join Votes v on v.PostId = p.Id
        left join Users vld on v.UserId = vld.Id
    group by p.Id
), CTEUserBadgesCounts AS (
    select
        b.UserId,
        count(b.Id) filter(where b.Class = 1) as GoldBadges,
        count(b.Id) filter(where b.Class = 2) as SilverBadges,
        count(b.Id) filter(where b.Class = 3) as BronzeBadges,
        count(b.Id) as TotalBadges
    from
        Badges b
    group by b.UserId
), CTELinkHierarchyPaths AS (
    select
        pl.PostId,
        pl.RelatedPostId,
        1 as Depth,
        array[pl.PostId, pl.RelatedPostId] as PathPosts
    from
        PostLinks pl
    union all
    select
        lh.PostId,
        pl.RelatedPostId,
        lh.Depth + 1,
        lh.PathPosts || pl.RelatedPostId
    from
        CTELinkHierarchyPaths lh
        join PostLinks pl on lh.RelatedPostId = pl.PostId
    where
        lh.Depth < 3
        and not pl.RelatedPostId = any(lh.PathPosts)
), CTEClosedQuestionsWithReasonText AS (
    select
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseDate
    from
        PostHistory ph 
        join CloseReasonTypes cr on cast(ph.Comment as int) = cr.Id
    where ph.PostHistoryTypeId = 10
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.Views,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    sq.QuestionId,
    sq.Title,
    sq.Score as QuestionScore,
    sq.AcceptedAnswerId,
    sq.AcceptedAnswerScore,
    sq.ScoreRank as AcceptedAnswerScoreRank,
    coalesce(cst.CommentCountTotal,0) as QuestionCommentCount,
    coalesce(pldr.LikeDislikeRatio, -1) as QuestionLikeDislikeRatio,
    plh.Count(postid) as LinkPathCount,
    closeinfo.CloseReason as QuestionCloseReason,
    last_act.MaxLastActivity,
    dense_rank() over (order by u.Reputation desc nulls last) as OverallUserReputationRank
from
    CTEUserReputation u
    left join CTEUserBadgesCounts ub on ub.UserId = u.Id
    inner join CTEQuestionWithAcceptedAnswer sq on sq.OwnerUserId = u.Id
    left join CTECommentsStats cst on cst.PostId = sq.QuestionId
    left join CTEPostLikesDislikesRatio pldr on pldr.Id = sq.QuestionId
    left join (select PostId, count(*) as Count from CTELinkHierarchyPaths group by PostId) plh on plh.PostId = sq.QuestionId
    left join CTEClosedQuestionsWithReasonText closeinfo on closeinfo.PostId = sq.QuestionId
    left join lateral (
        select
            max(p.LastActivityDate) as MaxLastActivity
        from
            Posts p
        where
            p.OwnerUserId = u.Id
    ) last_act on true
where
    u.Location is not null
    and u.Reputation > (
        select avg(Reputation) from Users where Location = u.Location
    )
    and sq.CreationDate >= date_trunc('year', current_date) - interval '2 years'
order by
    u.Reputation desc nulls last,
    sq.Score desc 
limit 100;