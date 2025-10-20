with UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as Questions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as Answers,
        coalesce(avg(p.Score),0) as AvgPostScore,
        coalesce(sum(case when p.ViewCount is not null then p.ViewCount else 0 end),0) as TotalViews,
        row_number() over (order by count(distinct p.Id) desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
), PostVotesAgg as (
    select 
        p.Id as PostId,
        count(v.Id) filter (where vt.Name = 'UpMod') as UpVotes,
        count(v.Id) filter (where vt.Name = 'DownMod') as DownVotes,
        count(v.Id) filter (where vt.Name = 'Favorite') as Favorites,
        sum(v.BountyAmount) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by p.Id
), RecentEditedPosts as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        ph.CreationDate as LastEditDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorDisplayName,
        ph.PostHistoryTypeId,
        row_number() over (partition by p.Id order by ph.CreationDate desc) as rn
    from Posts p
    join PostHistory ph on ph.PostId = p.Id
    where ph.PostHistoryTypeId in (4,5,6,7,8,9)
), TopTags as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        p.Title as ExcerptTitle,
        p2.Title as WikiTitle,
        case when t.IsModeratorOnly then 1 else 0 end as IsModeratorOnly,
        case when t.IsRequired then 1 else 0 end as IsRequired
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    left join Posts p2 on p2.Id = t.WikiPostId
    where t.Count > 1000
), DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
), QuestionCloseInfo as (
    select 
        ph.PostId,
        c.Name as CloseReason,
        ph.CreationDate as CloseDate,
        ph.UserId as CloseVoterId
    from PostHistory ph
    left join CloseReasonTypes c on c.Id = (case when trim(ph.Comment) ~ '^[0-9]+$' then cast(ph.Comment as integer) else null end)
    where ph.PostHistoryTypeId = 10
), UserBadgeRanks as (
    select 
        b.UserId,
        b.Class,
        count(b.Id) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
), UserBadgesSummary as (
    select 
        ub.UserId,
        max(case when ub.Class = 1 then ub.BadgeCount else 0 end) as GoldBadges,
        max(case when ub.Class = 2 then ub.BadgeCount else 0 end) as SilverBadges,
        max(case when ub.Class = 3 then ub.BadgeCount else 0 end) as BronzeBadges
    from UserBadgeRanks ub
    group by ub.UserId
)
select 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ups.AvgPostScore,
    ups.TotalViews,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    d.Count as DuplicateCount,
    qci.CloseReason,
    qci.CloseDate,
    qci.CloseVoterId,
    top.TagsSummary,
    pva.UpVotes,
    pva.DownVotes,
    pva.Favorites,
    pva.TotalBounty,
    rep.LastEditUser,
    rep.LastEditDate
from UserPostStats ups
left join UserBadgesSummary ub on ub.UserId = ups.UserId
left join (
    select 
        dl.PostId,
        count(*) as Count
    from DuplicateLinks dl
    group by dl.PostId
) d on d.PostId = ups.UserId
left join (
    select 
        ph.PostId,
        ph.CloseReason,
        ph.CloseDate,
        ph.CloseVoterId
    from QuestionCloseInfo ph
) qci on qci.PostId = ups.UserId
left join (
    select 
        p.OwnerUserId,
        sum(pva.UpVotes) as UpVotes,
        sum(pva.DownVotes) as DownVotes,
        sum(pva.Favorites) as Favorites,
        sum(coalesce(pva.TotalBounty,0)) as TotalBounty
    from Posts p
    left join PostVotesAgg pva on pva.PostId = p.Id
    group by p.OwnerUserId
) pva on pva.OwnerUserId = ups.UserId
left join (
    select 
        rep.OwnerUserId,
        rep2.EditorUserId as LastEditUser,
        rep2.LastEditDate
    from Posts rep
    join RecentEditedPosts rep2 on rep2.Id = rep.Id and rep2.rn = 1
    group by rep.OwnerUserId, rep2.EditorUserId, rep2.LastEditDate
) rep on rep.OwnerUserId = ups.UserId
left join (
    select 
        ups2.UserId,
        string_agg(distinct t.TagName, ', ') as TagsSummary
    from Posts p
    join UserPostStats ups2 on ups2.UserId = p.OwnerUserId
    cross join lateral
        (select unnest(string_to_array(coalesce(p.Tags,''), '><')) as TagName) as t
    group by ups2.UserId
) top on top.UserId = ups.UserId
where ups.TotalPosts > 50
order by ups.TotalPosts desc, ups.AvgPostScore desc
limit 100;