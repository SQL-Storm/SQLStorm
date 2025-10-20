with RecursiveBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        cast(count(b.Id) as bigint) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, b.Class
), RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as PostRank
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
), LatestComments as (
    select
        c.PostId,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        u.DisplayName as CommentUserName,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as CommentRank
    from Comments c
    left join Users u on c.UserId = u.Id
), PostLinksWithTypes as (
    select
        pl.PostId,
        lt.Name as LinkTypeName,
        count(*) as LinkCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId, lt.Name
), CTE_QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        case 
            when p.ClosedDate is null then 0
            else 1
        end as IsClosed,
        sum(case when plwt.LinkTypeName = 'Duplicate' then plwt.LinkCount else 0 end) as DuplicateLinks,
        sum(case when plwt.LinkTypeName = 'Linked' then plwt.LinkCount else 0 end) as LinkedPosts
    from Posts p
    left join PostLinksWithTypes plwt on p.Id = plwt.PostId
    where p.PostTypeId = 1
    group by
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        p.ClosedDate
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    coalesce(gbc.BadgeCount, 0) as GoldBadges,
    coalesce(sbc.BadgeCount, 0) as SilverBadges,
    coalesce(bbc.BadgeCount, 0) as BronzeBadges,
    latestQ.Id as LatestQuestionId,
    latestQ.Title as LatestQuestionTitle,
    latestQ.CreationDate as LatestQuestionDate,
    latestQ.Score as LatestQuestionScore,
    latestQ.ViewCount as LatestQuestionViews,
    latestAns.Id as LatestAnswerId,
    latestAns.CreationDate as LatestAnswerDate,
    latestAns.Score as LatestAnswerScore,
    coalesce(cmnt.CommentText, 'No recent comment') as LatestCommentText,
    coalesce(cmnt.CommentDate, to_timestamp(0)) as LatestCommentDate,
    coalesce(cmnt.CommentUserName, 'Anonymous') as LatestCommentUser,
    qs.AnswerCount,
    qs.IsClosed,
    qs.DuplicateLinks,
    qs.LinkedPosts,
    qs.UpVotes,
    qs.DownVotes,
    qs.CommentCount,
    case
        when qs.Score > 100 then 'Hot Question'
        when qs.Score between 50 and 100 then 'Popular Question'
        else 'Normal Question'
    end as QuestionPopularity,
    substring(
        array_to_string(
            string_to_array(coalesce(qs.Tags, ''), '><'), 
            ' | '
        )
        from 1 for 100
    ) as TagsSummary,
    dense_rank() over (order by u.Reputation desc) as ReputationRank
from Users u
left join RecursiveBadgeCounts gbc on u.Id = gbc.UserId and gbc.Class = 1
left join RecursiveBadgeCounts sbc on u.Id = sbc.UserId and sbc.Class = 2
left join RecursiveBadgeCounts bbc on u.Id = bbc.UserId and bbc.Class = 3
left join (
    select * from RankedPosts
    where PostTypeId = 1 and PostRank = 1
) latestQ on u.Id = latestQ.OwnerUserId
left join (
    select * from RankedPosts
    where PostTypeId = 2 and PostRank = 1
) latestAns on u.Id = latestAns.OwnerUserId
left join LatestComments cmnt on latestQ.Id = cmnt.PostId and cmnt.CommentRank = 1
left join CTE_QuestionStats qs on latestQ.Id = qs.QuestionId
where u.Reputation > 1000
group by
    u.Id,
    u.DisplayName,
    u.Reputation,
    gbc.BadgeCount,
    sbc.BadgeCount,
    bbc.BadgeCount,
    latestQ.Id,
    latestQ.Title,
    latestQ.CreationDate,
    latestQ.Score,
    latestQ.ViewCount,
    latestAns.Id,
    latestAns.CreationDate,
    latestAns.Score,
    cmnt.CommentText,
    cmnt.CommentDate,
    cmnt.CommentUserName,
    qs.AnswerCount,
    qs.IsClosed,
    qs.DuplicateLinks,
    qs.LinkedPosts,
    qs.UpVotes,
    qs.DownVotes,
    qs.CommentCount,
    qs.Score,
    qs.Tags
order by ReputationRank, LatestQuestionDate desc
limit 100;