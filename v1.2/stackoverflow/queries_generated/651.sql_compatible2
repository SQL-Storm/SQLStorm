with recursive RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.ViewCount,0) as ViewCount,
        coalesce(p.Score,0) as Score,
        p.OwnerUserId,
        1 as Level
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where coalesce(t.IsModeratorOnly, false) = false and coalesce(t.IsRequired, false) = false

    union all

    select
        rtc.TagId,
        rtc.TagName,
        rtc.Count,
        rtc.ViewCount + coalesce(p.ViewCount,0),
        rtc.Score + coalesce(p.Score,0),
        rtc.OwnerUserId,
        rtc.Level + 1
    from RecursiveTagCounts rtc
    join Posts p on p.ParentId = rtc.OwnerUserId
    where rtc.Level < 2
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.Date > (cast('2024-10-01' as date) - interval '365 days')
    group by b.UserId, b.Class
),
UserReputationWindows as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        row_number() over (partition by u.Location order by u.Reputation desc) as RepRankInLocation,
        count(*) over (partition by u.Location) as UsersInLocation,
        sum(u.UpVotes) over (partition by u.Location) as TotalUpVotesInLocation
    from Users u
    where u.Location is not null
),
PostStats as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        (select count(*) from Comments c where c.PostId = p.Id and c.Score > 0) as PositiveCommentCount,
        (select max(v.CreationDate) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as LastUpvoteDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserTopPostRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
PostCloseHistory as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as ClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as ReopenedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
),
PostLinkInfo as (
    select
        pl.PostId,
        count(case when pl.LinkTypeId = 1 then 1 end) as LinkedCount,
        count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
),
HighActivityUsers as (
    select
        u.Id,
        u.DisplayName,
        count(p.Id) as TotalPosts,
        sum(p.Score) as TotalPostScore,
        sum(ps.PositiveCommentCount) as TotalPositiveComments,
        coalesce(sum(v.BountyAmount),0) as TotalBountyAwarded
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostStats ps on ps.Id = p.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9)
    group by u.Id, u.DisplayName
    having count(p.Id) > 50 and coalesce(sum(p.Score),0) > 100
),
ComplexUserMetrics as (
    select
        h.Id as UserId,
        h.DisplayName,
        h.TotalPosts,
        h.TotalPostScore,
        h.TotalPositiveComments,
        h.TotalBountyAwarded,
        coalesce(ubr.GoldBadges,0) as GoldBadgeCount,
        coalesce(ubr.SilverBadges,0) as SilverBadgeCount,
        coalesce(ubr.BronzeBadges,0) as BronzeBadgeCount,
        urw.RepRankInLocation,
        urw.UsersInLocation,
        urw.TotalUpVotesInLocation
    from HighActivityUsers h
    left join (
        select
            UserId,
            sum(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
            sum(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
            sum(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
        from UserBadgeRanks
        group by UserId
    ) ubr on ubr.UserId = h.Id
    left join UserReputationWindows urw on urw.UserId = h.Id
),
FinalPostDetails as (
    select
        ps.Id,
        ps.PostTypeId,
        ps.CreationDate,
        ps.Score,
        ps.ViewCount,
        ps.Tags,
        ps.OwnerUserId,
        coalesce(pl.LinkedCount,0) as LinkedCount,
        coalesce(pl.DuplicateCount,0) as DuplicateCount,
        pch.ClosedDate,
        pch.ReopenedDate,
        pch.CloseReasonId,
        ps.PositiveCommentCount,
        ps.LastUpvoteDate,
        ps.UserTopPostRank,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        case
            when ps.Score > 10 and ps.ViewCount > 1000 then 'High Impact'
            when ps.Score between 1 and 10 then 'Moderate Impact'
            else 'Low Impact'
        end as ImpactCategory,
        row_number() over (partition by ps.PostTypeId order by ps.Score desc, ps.ViewCount desc) as RankInType
    from PostStats ps
    left join PostLinkInfo pl on pl.PostId = ps.Id
    left join PostCloseHistory pch on pch.PostId = ps.Id
    left join Users u on u.Id = ps.OwnerUserId
)
select
    fud.UserId,
    fud.DisplayName,
    fud.TotalPosts,
    fud.TotalPostScore,
    fud.TotalPositiveComments,
    fud.TotalBountyAwarded,
    fud.GoldBadgeCount,
    fud.SilverBadgeCount,
    fud.BronzeBadgeCount,
    fud.RepRankInLocation,
    fud.UsersInLocation,
    fud.TotalUpVotesInLocation,
    fpd.Id as TopPostId,
    fpd.Score as TopPostScore,
    fpd.ViewCount as TopPostViews,
    fpd.CreationDate as TopPostCreationDate,
    fpd.ImpactCategory,
    fpd.RankInType,
    string_agg(distinct rtc.TagName || ' (' || cast(rtc.Count as varchar) || ')', ', ') as TagsAssociated
from ComplexUserMetrics fud
join FinalPostDetails fpd on fpd.OwnerUserId = fud.UserId and fpd.UserTopPostRank = 1
left join RecursiveTagCounts rtc on rtc.OwnerUserId = fud.UserId
where coalesce(fud.GoldBadgeCount,0) >= 1 or coalesce(fud.TotalBountyAwarded,0) > 500
group by
    fud.UserId,
    fud.DisplayName,
    fud.TotalPosts,
    fud.TotalPostScore,
    fud.TotalPositiveComments,
    fud.TotalBountyAwarded,
    fud.GoldBadgeCount,
    fud.SilverBadgeCount,
    fud.BronzeBadgeCount,
    fud.RepRankInLocation,
    fud.UsersInLocation,
    fud.TotalUpVotesInLocation,
    fpd.Id,
    fpd.Score,
    fpd.ViewCount,
    fpd.CreationDate,
    fpd.ImpactCategory,
    fpd.RankInType
order by fud.TotalPostScore desc, fud.GoldBadgeCount desc, fud.TotalBountyAwarded desc
limit 100;