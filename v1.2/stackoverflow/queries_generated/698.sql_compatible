with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(u.AboutMe, '') as AboutMe,
        p.Id as LatestPostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
UserTopPosts as (
    select * from RecursiveUserActivity where PostRank <= 3
),
PostCommentsCount as (
    select 
        c.PostId, 
        count(*) as CommentCount,
        sum(case when c.UserId is null then 0 else 1 end) as CommentsByRegisteredUsers
    from Comments c
    group by c.PostId
),
PostVotesSummary as (
    select 
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
UserBadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
DuplicatePostLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
UserTopDuplicatePosts as (
    select distinct utp.UserId, utp.LatestPostId, dpl.RelatedPostId
    from UserTopPosts utp
    left join DuplicatePostLinks dpl on dpl.PostId = utp.LatestPostId
),
PostsWithCloseInfo as (
    select 
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as ClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as ReopenedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
),
RankedUserPosts as (
    select 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.CreationDate,
        ps.UpVotes,
        ps.DownVotes,
        ps.Favorites,
        pc.CommentCount,
        pc.CommentsByRegisteredUsers,
        pci.ClosedDate,
        pci.ReopenedDate,
        pci.CloseReasonId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    left join PostVotesSummary ps on ps.PostId = p.Id
    left join PostCommentsCount pc on pc.PostId = p.Id
    left join PostsWithCloseInfo pci on pci.PostId = p.Id
    where p.OwnerUserId is not null
),
UserAggregatedStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        count(rp.Id) as TotalPosts,
        avg(rp.Score) as AvgPostScore,
        max(rp.ViewCount) as MaxPostViews,
        sum(coalesce(rp.CommentCount,0)) as TotalComments,
        sum(coalesce(rp.Favorites,0)) as TotalFavorites,
        sum(case when rp.ClosedDate is not null then 1 else 0 end) as ClosedPostsCount,
        sum(case when cast(rp.CloseReasonId as integer) in (101,102,103,104,105) then 1 else 0 end) as SpecificCloseReasonsCount
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join RankedUserPosts rp on rp.OwnerUserId = u.Id and rp.ScoreRank <= 5
    group by u.Id, u.DisplayName, u.Reputation, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges
),
FilteredUsers as (
    select * from UserAggregatedStats
    where Reputation > 5000 and TotalPosts > 10 and GoldBadges >= 1
)
select 
    fu.UserId,
    fu.DisplayName,
    fu.Reputation,
    fu.GoldBadges,
    fu.SilverBadges,
    fu.BronzeBadges,
    fu.TotalPosts,
    round(fu.AvgPostScore,2) as AvgPostScore,
    fu.MaxPostViews,
    fu.TotalComments,
    fu.TotalFavorites,
    fu.ClosedPostsCount,
    fu.SpecificCloseReasonsCount,
    string_agg(distinct t.TagName, ', ') as TopTags,
    max(case when rp.ScoreRank = 1 then rp.Title end) as TopScoringPostTitle,
    max(case when rp.ScoreRank = 1 then rp.Score end) as TopScoringPostScore,
    max(case when rp.ScoreRank = 1 then rp.ViewCount end) as TopScoringPostViews
from FilteredUsers fu
left join RankedUserPosts rp on rp.OwnerUserId = fu.UserId and rp.ScoreRank = 1
left join Posts p on p.Id = rp.Id
left join lateral (
    select trim(both '<>' from tag) as TagName from (
        select regexp_split_to_table(coalesce(p.Tags,''), '><') as tag
    ) s
) tags on true
left join Tags t on t.TagName = tags.TagName
group by fu.UserId, fu.DisplayName, fu.Reputation, fu.GoldBadges, fu.SilverBadges, fu.BronzeBadges, fu.TotalPosts, fu.AvgPostScore, fu.MaxPostViews, fu.TotalComments, fu.TotalFavorites, fu.ClosedPostsCount, fu.SpecificCloseReasonsCount
order by fu.Reputation desc, fu.GoldBadges desc, fu.TotalPosts desc
limit 50;