-- {"query": "2206.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1479}
with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = true then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoresWithUser as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostRank,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc nulls last) as PostTypeScoreRank,
        p.CreationDate,
        p.Title,
        p.Tags
    from Posts p
    where p.Score is not null
),
TopPostsWithBadgeStats as (
    select
        p.Id as PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.PostTypeId,
        u.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TagBasedBadges,
        p.UserPostRank,
        p.PostTypeScoreRank
    from PostScoresWithUser p
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeCounts ubc on ubc.UserId = p.OwnerUserId
    where p.UserPostRank <= 5
),
PostLinksAggregate as (
    select
        pl.PostId,
        count(case when pl.LinkTypeId = 1 then 1 end) as LinkedCount,
        count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
),
LatestCommentPerPost as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        c.UserId as CommentUserId,
        c.UserDisplayName
    from Comments c
    order by c.PostId, c.CreationDate desc
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where crt.Id is not null
),
PostsWithAggregates as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        plagg.LinkedCount,
        plagg.DuplicateCount,
        lcp.CommentId,
        lcp.CommentText,
        lcp.CommentDate,
        coalesce(pcr.CloseReason, 'Not Closed') as CloseReason,
        pcr.CloseDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last) as RankByScoreInType,
        count(*) over (partition by p.PostTypeId) as TotalPostsOfType,
        p.OwnerUserId
    from Posts p
    left join PostLinksAggregate plagg on plagg.PostId = p.Id
    left join LatestCommentPerPost lcp on lcp.PostId = p.Id
    left join PostCloseReasons pcr on pcr.PostId = p.Id
),
HighImpactPosts as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        p.LinkedCount,
        p.DuplicateCount,
        p.CommentId,
        p.CommentText,
        p.CommentDate,
        p.CloseReason,
        p.CloseDate,
        p.RankByScoreInType,
        p.TotalPostsOfType,
        u.DisplayName as OwnerDisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TagBasedBadges,
        case 
            when p.Tags is not null then array_to_string(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), ', ')
            else ''
        end as ParsedTags,
        case
            when p.Score >= 100 and u.Reputation >= 1000 then 'HighReputationHighScore'
            when p.Score >= 100 then 'HighScore'
            when u.Reputation >= 1000 then 'HighReputation'
            else 'Normal'
        end as ImpactCategory
    from PostsWithAggregates p
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeCounts ub on ub.UserId = u.Id
    where p.Score is not null
),
CorrelatedAnswerCounts as (
    select
        q.Id as QuestionId,
        count(a.Id) as AnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
FinalSelection as (
    select
        hip.Id as PostId,
        hip.Title,
        hip.ParsedTags,
        hip.Score,
        hip.ViewCount,
        hip.PostTypeId,
        hip.LinkedCount,
        hip.DuplicateCount,
        hip.CommentId,
        hip.CommentText,
        hip.CommentDate,
        hip.CloseReason,
        hip.CloseDate,
        hip.RankByScoreInType,
        hip.TotalPostsOfType,
        hip.OwnerDisplayName,
        hip.Reputation,
        hip.Views,
        hip.UpVotes,
        hip.DownVotes,
        hip.GoldBadges,
        hip.SilverBadges,
        hip.BronzeBadges,
        hip.TagBasedBadges,
        hip.ImpactCategory,
        coalesce(cac.AnswerCount, 0) as AnswerCount,
        case 
            when hip.CloseReason <> 'Not Closed' then true
            else false
        end as IsClosed
    from HighImpactPosts hip
    left join CorrelatedAnswerCounts cac on cac.QuestionId = hip.Id
    where hip.RankByScoreInType <= 100
)
select *
from FinalSelection
where (ImpactCategory = 'HighReputationHighScore' or ImpactCategory = 'HighScore')
  and (AnswerCount > 5 or ViewCount > 1000)
order by Score desc, Reputation desc, ViewCount desc
limit 50;