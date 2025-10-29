-- {"query": "2511.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1291} 
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank,
        case 
            when p.Title is not null then p.Title
            else substr(p.Body, 1, 40) || coalesce('...', '')
        end as Snippet,
        -- Count comments for this post
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        -- Count badges for user up to post creation date
        (select count(*) from Badges b where b.UserId = u.Id and b.Date <= p.CreationDate) as BadgesBeforePost,
        -- Max badge class before post creation
        (select max(b.Class) from Badges b where b.UserId = u.Id and b.Date <= p.CreationDate) as MaxBadgeClassBeforePost
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation >= 1000
),
UserComplexStats as (
    select
        rup.UserId,
        rup.DisplayName,
        count(distinct rup.PostId) as TotalPosts,
        sum(case when rup.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when rup.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        avg(rup.Score) as AvgPostScore,
        sum(rup.ViewCount) as TotalViews,
        sum(rup.CommentCount) as TotalComments,
        max(rup.BadgesBeforePost) as MaxBadgesBeforeAnyPost,
        max(rup.MaxBadgeClassBeforePost) as MaxBadgeLevelBeforeAnyPost,
        -- Window function to get rank of user by number of posts in descending order
        rank() over (order by count(distinct rup.PostId) desc) as UserPostRank
    from RecursiveUserPosts rup
    group by rup.UserId, rup.DisplayName
),
DuplicateLinkedPosts as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        u.DisplayName as OwnerName,
        pl.CreationDate as LinkCreation,
        lt.Name as LinkTypeName
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u on u.Id = p1.OwnerUserId
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3 -- Duplicates
),
UserBadgesWithRank as (
    select 
        b.Id,
        b.UserId,
        b.Name,
        b.Date,
        b.Class,
        u.Reputation,
        row_number() over (partition by b.UserId order by b.Date asc) as BadgeSequence,
        dense_rank() over (order by u.Reputation desc) as UserRepRank,
        -- String concat to produce badge with class text
        concat(
            b.Name,
            case b.Class 
                when 1 then ' (Gold)'
                when 2 then ' (Silver)'
                when 3 then ' (Bronze)'
                else ' (Unknown)' 
            end
        ) as BadgeDisplayName
    from Badges b
    inner join Users u on u.Id = b.UserId
    where b.Date > (current_timestamp - interval '5 years')
),
LatestPostHistoryByType as (
    select distinct on (ph.PostId, ph.PostHistoryTypeId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        ph.Text
    from PostHistory ph
    order by ph.PostId, ph.PostHistoryTypeId, ph.CreationDate desc
)
select
    ucs.UserId,
    ucs.DisplayName,
    ucs.TotalPosts,
    ucs.QuestionsCount,
    ucs.AnswersCount,
    ucs.AvgPostScore,
    ucs.TotalViews,
    ucs.TotalComments,
    ucs.MaxBadgesBeforeAnyPost,
    ucs.MaxBadgeLevelBeforeAnyPost,
    ucs.UserPostRank,
    dup.PostId as DuplicatePostId,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostId,
    dup.RelatedPostTitle,
    dup.OwnerName as DuplicatePostOwner,
    dup.LinkCreation,
    dup.LinkTypeName,
    ubwr.Name as BadgeName,
    ubwr.BadgeDisplayName,
    ubwr.Date as BadgeDate,
    ubwr.Class as BadgeClass,
    ubwr.UserRepRank,
    ph.LatestCloseDate,
    ph.LatestReopenDate,
    ph.LatestDeleteDate
from UserComplexStats ucs
left join DuplicateLinkedPosts dup on dup.OwnerName = ucs.DisplayName
left join UserBadgesWithRank ubwr on ubwr.UserId = ucs.UserId and ubwr.BadgeSequence = 1
left join (
    select 
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LatestCloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LatestReopenDate,
        max(case when ph.PostHistoryTypeId = 12 then ph.CreationDate end) as LatestDeleteDate
    from PostHistory ph
    group by ph.PostId
) ph on ph.PostId = dup.PostId
where ucs.UserPostRank <= 100
and (ucs.AvgPostScore > 5 or ucs.TotalComments > 50)
and (dup.PostId is null or dup.LinkCreation > (current_timestamp - interval '1 year'))
order by ucs.UserPostRank, dup.LinkCreation desc nulls last;