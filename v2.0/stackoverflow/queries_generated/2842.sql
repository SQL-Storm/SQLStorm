-- {"query": "2842.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1437} 
with RecursiveCTE as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) as TagCount,
        row_number() over(partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn,
        1 as depth
    from
        Posts p
    where
        p.PostTypeId = 1
        and p.Score > 10
        and p.Tags is not null
    union all
    select
        c.Id,
        c.PostTypeId,
        c.OwnerUserId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.Title,
        r.TagCount,
        r.rn,
        r.depth + 1
    from
        Posts c
        join RecursiveCTE r on c.ParentId = r.Id
    where
        c.PostTypeId = 2
        and c.Score > 0
),
UserBadgeAgg as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter(where b.Class = 1) as GoldBadges,
        count(b.Id) filter(where b.Class = 2) as SilverBadges,
        count(b.Id) filter(where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges,
        rank() over(order by count(b.Id) desc) as BadgeRank
    from
        Users u
        left join Badges b on b.UserId = u.Id
    group by
        u.Id, u.DisplayName
),
PostCommentsAgg as (
    select
        p.Id as PostId,
        count(c.Id) as CommentCount,
        string_agg(distinct substr(c.Text,1,15), ' | ') as SampleCommentSnippets,
        max(c.CreationDate) as LastCommentDate
    from
        Posts p
        left join Comments c on c.PostId = p.Id
    group by
        p.Id
),
FilteredPostHistory as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text,
        row_number() over(partition by ph.PostId order by ph.CreationDate desc) as rn
    from
        PostHistory ph
    where
        ph.PostHistoryTypeId in (4,5,6,10,11)
),
TopPostHistories as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text
    from
        FilteredPostHistory ph
    where
        ph.rn = 1
),
FinalSelection as (
    select
        r.PostTypeId,
        r.Id as PostId,
        r.OwnerUserId,
        u.DisplayName as OwnerName,
        r.CreationDate,
        r.Score,
        r.ViewCount,
        r.TagCount,
        pb.GoldBadges,
        pb.SilverBadges,
        pb.BronzeBadges,
        pb.TagBasedBadges,
        pc.CommentCount,
        pc.SampleCommentSnippets,
        pc.LastCommentDate,
        tph.PostHistoryTypeId,
        tph.Comment as CloseReason,
        tph.Text as LastEditTextSample,
        dense_rank() over(partition by r.PostTypeId order by r.Score desc, r.ViewCount desc) as RankWithinType,
        case 
            when r.Score > 100 then 'High Score'
            when r.Score between 50 and 100 then 'Medium Score'
            else 'Low Score'
        end as ScoreCategory,
        coalesce(u.Location, 'Unknown') as UserLocation,
        case when pb.GoldBadges > 0 then true else false end as HasGoldBadge,
        substring(r.Title from 1 for 50) || coalesce(' ... [' || pb.BronzeBadges::text || ' Bronze Badges]', '') as ShortTitleWithBadgeInfo
    from
        RecursiveCTE r
        left join Users u on u.Id = r.OwnerUserId
        left join UserBadgeAgg pb on pb.UserId = r.OwnerUserId
        left join PostCommentsAgg pc on pc.PostId = r.Id
        left join TopPostHistories tph on tph.PostId = r.Id
    where
        r.depth = 1
)
select 
    fs.PostTypeId,
    fs.PostId,
    fs.OwnerUserId,
    fs.OwnerName,
    fs.CreationDate,
    fs.Score,
    fs.ViewCount,
    fs.TagCount,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.TagBasedBadges,
    fs.CommentCount,
    fs.SampleCommentSnippets,
    fs.LastCommentDate,
    fs.PostHistoryTypeId,
    fs.CloseReason,
    substring(fs.LastEditTextSample from 1 for 100) as LastEditTextSample,
    fs.RankWithinType,
    fs.ScoreCategory,
    fs.UserLocation,
    fs.HasGoldBadge,
    fs.ShortTitleWithBadgeInfo
from
    FinalSelection fs
where
    fs.RankWithinType <= 100
union
select
    pt.Id as PostTypeId,
    p.Id as PostId,
    p.OwnerUserId,
    u.DisplayName as OwnerName,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    0 as TagCount,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as TagBasedBadges,
    0 as CommentCount,
    null as SampleCommentSnippets,
    null as LastCommentDate,
    null as PostHistoryTypeId,
    null as CloseReason,
    null as LastEditTextSample,
    null as RankWithinType,
    'N/A' as ScoreCategory,
    coalesce(u.Location, 'Unknown') as UserLocation,
    false as HasGoldBadge,
    substring(coalesce(p.Title,'[No Title]') from 1 for 50) as ShortTitleWithBadgeInfo
from
    Posts p
    join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
where
    p.PostTypeId NOT IN (1,2)
order by
    PostTypeId,
    Score desc nulls last,
    ViewCount desc nulls last,
    CreationDate desc;