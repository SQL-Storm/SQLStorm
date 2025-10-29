with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        b.Date as BadgeDate,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where (b.TagBased = false) or (b.TagBased is null)
), RankedTopBadges as (
    select UserId, DisplayName, BadgeName, BadgeClass, BadgeDate
    from RecursiveUserBadges
    where BadgeRank <= 5
), PostScoreStats as (
    select
        p.OwnerUserId,
        avg(case when p.Score > 0 then p.Score end) as AvgPositiveScore,
        avg(case when p.Score <= 0 then p.Score end) as AvgNonPositiveScore,
        count(*) as TotalPosts,
        count(distinct p.PostTypeId) as DistinctPostTypes,
        max(p.ViewCount) as MaxViewCount
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
    group by p.OwnerUserId
), UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(ph.Id) as TotalEdits,
        count(distinct ph.PostId) as DistinctPostsEdited,
        max(ph.CreationDate) as LastEditDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName
), ComplexPostsCTE as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        (select string_agg(lt.Name, ', ')
            from PostLinks pl
            join LinkTypes lt on pl.LinkTypeId = lt.Id
            where pl.PostId = p.Id
        ) as LinkTypeNames,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Accepted'
            else 'Open'
        end as Status,
        count(c.Id) over (partition by p.Id) as CommentCountWindow,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as PostRankByUser
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
), PostsWithDuplicateInfo as (
    select
        cp.*,
        exists (
            select 1 
            from PostLinks pl2 
            where pl2.PostId = cp.Id and pl2.LinkTypeId = 3
        ) as HasDuplicateLink
    from ComplexPostsCTE cp
), DetailedUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        pu.AvgPositiveScore,
        pu.AvgNonPositiveScore,
        pu.TotalPosts,
        pu.DistinctPostTypes,
        pu.MaxViewCount,
        ua.TotalEdits,
        ua.DistinctPostsEdited,
        ua.LastEditDate,
        coalesce(pb.BadgeCountGold, 0) as GoldBadges,
        coalesce(pb.BadgeCountSilver, 0) as SilverBadges,
        coalesce(pb.BadgeCountBronze, 0) as BronzeBadges
    from Users u
    left join PostScoreStats pu on pu.OwnerUserId = u.Id
    left join UserActivity ua on ua.UserId = u.Id
    left join (
        select 
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as BadgeCountGold,
            sum(case when Class = 2 then 1 else 0 end) as BadgeCountSilver,
            sum(case when Class = 3 then 1 else 0 end) as BadgeCountBronze
        from Badges
        group by UserId
    ) pb on pb.UserId = u.Id
)
select 
    dus.UserId,
    dus.DisplayName,
    dus.GoldBadges,
    dus.SilverBadges,
    dus.BronzeBadges,
    dus.TotalPosts,
    dus.AvgPositiveScore,
    dus.AvgNonPositiveScore,
    dus.MaxViewCount,
    dus.TotalEdits,
    dus.DistinctPostsEdited,
    dus.LastEditDate,
    count(distinct pwdi.Id) filter (where pwdi.HasDuplicateLink = true) as NumPostsWithDuplicates,
    count(distinct pwdi.Id) filter (where pwdi.Status = 'Closed') as NumClosedPosts,
    max(pwdi.CommentCountWindow) as MaxCommentsOnPost,
    -- for portability and to satisfy DISTINCT+ORDER BY rules, aggregate without DISTINCT and order externally via array_agg then string join
    replace(trim(both '[]' from cast(array_to_string(
        array_agg(pus.BadgeName order by pus.BadgeDate desc), ', ' ) as text)), '  ', ' ') as RecentBadges
from DetailedUserStats dus
left join PostsWithDuplicateInfo pwdi on pwdi.OwnerUserId = dus.UserId
left join RecursiveUserBadges pus on pus.UserId = dus.UserId and pus.BadgeRank <= 3
where dus.TotalPosts > 10 and dus.GoldBadges > 0
group by 
    dus.UserId, dus.DisplayName, dus.GoldBadges, dus.SilverBadges, dus.BronzeBadges,
    dus.TotalPosts, dus.AvgPositiveScore, dus.AvgNonPositiveScore, dus.MaxViewCount, dus.TotalEdits,
    dus.DistinctPostsEdited, dus.LastEditDate
order by dus.GoldBadges desc, dus.TotalPosts desc, dus.AvgPositiveScore desc
limit 50;