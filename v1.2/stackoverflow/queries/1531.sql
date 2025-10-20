with recursive TagCombos as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(coalesce(p.Tags, ''), 2, length(coalesce(p.Tags, '')) - 2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1
),
BadgeStats as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivityRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        rank() over (order by u.Reputation desc, u.CreationDate asc) as ReputationRank,
        dense_rank() over (partition by u.Location order by u.UpVotes desc NULLS LAST) as LocationUpvoteRank,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= (cast('2024-10-01' as date) - interval '1 year')
    left join Comments c on c.UserId = u.Id and c.CreationDate >= (cast('2024-10-01' as date) - interval '1 year')
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.UpVotes
),
FilteredPostHInEditRollbacks as (
    select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate
    from PostHistory ph 
    where (ph.PostHistoryTypeId in (4, 7) or ph.PostHistoryTypeId in (5, 8))
      and ph.CreationDate > (cast('2024-10-01' as date) - interval '6 months')
),
LinkedPostRanks as (
    select 
       pl.PostId,
       pl.RelatedPostId,
       pl.LinkTypeId,
       row_number() over (partition by pl.PostId, pl.LinkTypeId order by pl.CreationDate desc) as recent_link_rank
    from PostLinks pl
    where pl.LinkTypeId in (1, 3)
),
RecentObservedPosts as (
    select distinct 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.Title,
        length(p.Body) as BodyLength,
        p.Score,
        p.ViewCount,
        p.CreationDate
    from Posts p
),
RecursiveAncestors as (
    select p.Id as ParentPostId, p.Id as CurrentAncestor, 0 as Level
    from Posts p
    where p.ParentId is null

    union all

    select chq.ParentId, ra.CurrentAncestor, ra.Level + 1
    from Posts chq
    join RecursiveAncestors ra on chq.Id = ra.ParentPostId
    where chq.ParentId is not null and ra.Level < 50
)

select 
    ubr.UserId,
    ubr.DisplayName,
    ubr.ReputationRank,
    ubr.LocationUpvoteRank,
    ubr.PostsCount,
    ubr.CommentsCount,
    bs_g.GoldBadgeCount,
    bs_s.SilverBadgeCount,
    bs_b.BronzeBadgeCount,
    tc_avg.TensorPathAverage,
    lr_root.CXEnteredPointStart,
    loc.TopAreaCnt,
    cntnty.cntnty,
    wirst.wirstwndsehir_strextrlenex,
    jb.struppleedit_strangelyPrepareref
from UserActivityRanks ubr
left join (
    select UserId, BadgeCount as GoldBadgeCount from BadgeStats where Class = 1
) bs_g on bs_g.UserId = ubr.UserId
left join (
    select UserId, BadgeCount as SilverBadgeCount from BadgeStats where Class = 2
) bs_s on bs_s.UserId = ubr.UserId
left join (
    select UserId, BadgeCount as BronzeBadgeCount from BadgeStats where Class = 3
) bs_b on bs_b.UserId = ubr.UserId
left join (
    select
        tc.PostId,
        avg(length(tc.TagName)) over (partition by tc.PostId) as TensorPathAverage
    from TagCombos tc
) tc_avg on tc_avg.PostId = ubr.UserId
left join (
    select
        pl.PostId,
        max(pl.CreationDate) as CXEnteredPointStart
    from PostLinks pl
    group by pl.PostId
) lr_root on lr_root.PostId = ubr.UserId
left join (
    select
        l.Location as Location,
        count(*) as TopAreaCnt
    from Users l
    group by l.Location
) loc on loc.Location = ubr.DisplayName
left join (
    select CAST(NULL AS integer) as cntnty
) cntnty on true
left join (
    select CAST(NULL AS text) as wirstwndsehir_strextrlenex
) wirst on true
left join (
    select CAST(NULL AS text) as struppleedit_strangelyPrepareref
) jb on true
group by
    ubr.UserId,
    ubr.DisplayName,
    ubr.ReputationRank,
    ubr.LocationUpvoteRank,
    ubr.PostsCount,
    ubr.CommentsCount,
    bs_g.GoldBadgeCount,
    bs_s.SilverBadgeCount,
    bs_b.BronzeBadgeCount,
    tc_avg.TensorPathAverage,
    lr_root.CXEnteredPointStart,
    loc.TopAreaCnt,
    cntnty.cntnty,
    wirst.wirstwndsehir_strextrlenex,
    jb.struppleedit_strangelyPrepareref;