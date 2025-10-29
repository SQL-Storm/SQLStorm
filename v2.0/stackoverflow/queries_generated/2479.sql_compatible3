with recursive RecursiveTags as (
    select 
        Id, 
        TagName, 
        Count,
        1 as Level,
        array[Id] as Path
    from Tags
    where IsModeratorOnly = false and IsRequired = false

    union all

    select 
        t.Id, 
        t.TagName, 
        t.Count,
        rt.Level + 1,
        rt.Path || t.Id
    from Tags t
    join PostLinks pl on pl.PostId = t.ExcerptPostId and pl.LinkTypeId = 1
    join RecursiveTags rt on rt.Id = pl.RelatedPostId
    where not t.Id = any(rt.Path)
        and rt.Level < 3
),
UserBadgeCounts as (
    select 
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBadge
    from Badges b
    group by b.UserId
),
UserPostScoreStats as (
    select 
        p.OwnerUserId as UserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
RecentPostHistoryEdits as (
    select 
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        count(*) as EditCount
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.PostId
),
PostWindowRank as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as RankByScore
    from Posts p
    where p.PostTypeId in (1,2)
),
TopRankedPosts as (
    select 
        pwr.*
    from PostWindowRank pwr
    where pwr.RankByScore <= 5
),
UserLinkStats as (
    select 
        p.OwnerUserId as UserId,
        count(distinct pl.Id) as OutboundLinks,
        count(distinct pl2.Id) as InboundLinks
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join PostLinks pl2 on pl2.RelatedPostId = p.Id
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
RecentHighScoreQuestions as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        (select count(*) from Comments c where c.PostId = p.Id and c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as RecentCommentCount,
        case 
            when p.ClosedDate is not null then 'Closed'
            else 'Open'
        end as Status
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
      and p.Score > 10
),
DistinctUserLocations as (
    select 
        distinct Location,
        count(*) over (partition by Location) as UsersPerLocation
    from Users
    where Location is not null and Location <> ''
),
UserDisplayNameNormalized as (
    select 
        u.Id,
        u.DisplayName,
        lower(trim(u.DisplayName)) as NormalizedName,
        length(u.DisplayName) as NameLength,
        u.Reputation
    from Users u
    where u.DisplayName is not null
),
UserNameDuplicates as (
    select 
        NormalizedName,
        count(*) as DuplicateCount
    from UserDisplayNameNormalized
    group by NormalizedName
    having count(*) > 1
),
UserNameWithDups as (
    select 
        u.Id,
        u.DisplayName,
        u.NormalizedName,
        u.NameLength,
        u.Reputation,
        d.DuplicateCount
    from UserDisplayNameNormalized u
    left join UserNameDuplicates d on d.NormalizedName = u.NormalizedName
),
FinalUserStats as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        upss.QuestionCount,
        upss.AnswerCount,
        upss.AvgPostScore,
        upss.MaxPostScore,
        upss.TotalQuestionViews,
        ubc.TotalBadges,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.HasTagBadge,
        uls.OutboundLinks,
        uls.InboundLinks,
        un.DuplicateCount,
        du.UsersPerLocation,
        u.Location
    from Users u
    left join UserPostScoreStats upss on upss.UserId = u.Id
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join UserLinkStats uls on uls.UserId = u.Id
    left join UserNameWithDups un on un.Id = u.Id
    left join DistinctUserLocations du on du.Location = u.Location
    where u.Reputation > 1000
)
select 
    f.DisplayName,
    f.Reputation,
    coalesce(f.QuestionCount,0) as Questions,
    coalesce(f.AnswerCount,0) as Answers,
    round(coalesce(f.AvgPostScore,0)::numeric,2) as AvgScore,
    coalesce(f.MaxPostScore,0) as MaxScore,
    coalesce(f.TotalQuestionViews,0) as Views,
    coalesce(f.TotalBadges,0) as TotalBadges,
    coalesce(f.GoldBadges,0) as Gold,
    coalesce(f.SilverBadges,0) as Silver,
    coalesce(f.BronzeBadges,0) as Bronze,
    case when f.HasTagBadge then 'Yes' else 'No' end as HasTagBadges,
    coalesce(f.OutboundLinks,0) as OutgoingLinks,
    coalesce(f.InboundLinks,0) as IncomingLinks,
    coalesce(f.DuplicateCount,0) as DuplicateDisplayNames,
    coalesce(f.UsersPerLocation,0) as UsersInLocation,
    string_agg(distinct rt.TagName, ', ') as RelatedTags,
    (
      select count(*) 
      from Posts p2
      where p2.OwnerUserId = f.Id
        and p2.Score > (
            select avg(p3.Score) 
            from Posts p3
            where p3.OwnerUserId = f.Id
        )
    ) as AboveAvgScorePosts
from FinalUserStats f
left join Posts p on p.OwnerUserId = f.Id
left join RecursiveTags rt on exists (
    -- match numeric tag ids inside p.Tags like "<123><456>"
    select 1
    from (
        select regexp_matches(p.Tags, '<([0-9]+)>', 'g') as m
    ) as matches
    where (matches.m)[1]::int = rt.Id
)
where true
group by 
    f.DisplayName, f.Reputation, f.QuestionCount, f.AnswerCount, f.AvgPostScore, f.MaxPostScore, f.TotalQuestionViews,
    f.TotalBadges, f.GoldBadges, f.SilverBadges, f.BronzeBadges, f.HasTagBadge, f.OutboundLinks, f.InboundLinks, 
    f.DuplicateCount, f.UsersPerLocation, f.Id
order by f.Reputation desc
limit 25;