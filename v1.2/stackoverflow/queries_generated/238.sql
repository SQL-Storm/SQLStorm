-- {"query": "238.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1628} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsersCTE as (
    select UserId, DisplayName, Reputation, QuestionCount, AnswerCount, CommentCount, TotalVotesReceived, UserRank
    from RecursiveUserActivity
    where UserRank <= 100
),
PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        p.LastActivityDate,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        p.CommunityOwnedDate,
        p.ContentLicense
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.CreationDate >= current_date - interval '1 year'
),
PostVotesAgg as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(coalesce(v.BountyAmount,0)) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
PostLinksAgg as (
    select
        pl.PostId,
        count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId end) as LinkedPostsCount,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicatePostsCount
    from PostLinks pl
    group by pl.PostId
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    group by ph.PostId, crt.Name
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
UserActivityWithBadges as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionCount,
        u.AnswerCount,
        u.CommentCount,
        u.TotalVotesReceived,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        coalesce(b.DistinctBadges,0) as DistinctBadges
    from TopUsersCTE u
    left join UserBadgeStats b on b.UserId = u.UserId
),
RankedPosts as (
    select
        pd.*,
        pva.UpVotes,
        pva.DownVotes,
        pva.Favorites,
        pva.TotalBounty,
        pla.LinkedPostsCount,
        pla.DuplicatePostsCount,
        phcr.CloseReasonName,
        phcr.CloseCount,
        row_number() over (partition by pd.PostTypeId order by pd.Score desc, pd.ViewCount desc) as PostRank
    from PostDetails pd
    left join PostVotesAgg pva on pva.PostId = pd.Id
    left join PostLinksAgg pla on pla.PostId = pd.Id
    left join PostHistoryCloseReasons phcr on phcr.PostId = pd.Id
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.CommentCount,
    u.TotalVotesReceived,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.DistinctBadges,
    p.Id as PostId,
    p.PostTypeName,
    p.Title,
    p.Score,
    p.ViewCount,
    p.UpVotes,
    p.DownVotes,
    p.Favorites,
    p.TotalBounty,
    p.LinkedPostsCount,
    p.DuplicatePostsCount,
    p.CloseReasonName,
    p.CloseCount,
    p.PostRank,
    -- Complex string expression combining tags and title with NULL logic
    case
        when p.Tags is not null and p.Title is not null then
            concat('Tags: ', replace(replace(p.Tags, '><', ', '), '<', ''), ' | Title: ', p.Title)
        when p.Tags is not null then
            concat('Tags: ', replace(replace(p.Tags, '><', ', '), '<', ''))
        when p.Title is not null then
            concat('Title: ', p.Title)
        else
            'No Title or Tags'
    end as TagTitleSummary,
    -- Window function to calculate average score per user over their posts
    avg(p.Score) over (partition by p.OwnerUserId) as AvgUserPostScore,
    -- Correlated subquery to get count of answers for the question if post is a question
    case when p.PostTypeId = 1 then
        (select count(*) from Posts ans where ans.ParentId = p.Id and ans.PostTypeId = 2)
    else null end as AnswerCountForQuestion,
    -- Complex predicate: filter posts with score above average score of all posts by user and with at least one upvote
    case when p.Score > avg(p.Score) over (partition by p.OwnerUserId) and p.UpVotes > 0 then 1 else 0 end as IsHighScoringWithUpvotes
from UserActivityWithBadges u
left join RankedPosts p on p.OwnerUserId = u.UserId
where p.PostRank <= 5
order by u.Reputation desc, p.Score desc, p.ViewCount desc
limit 500;