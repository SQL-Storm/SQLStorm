-- {"query": "2903.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1907} 
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        1 as Depth
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
    union all
    select
        rup.UserId,
        rup.DisplayName,
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        rup.Depth + 1
    from RecursiveUserPosts rup
    join Posts p on p.ParentId = rup.PostId
    where rup.Depth < 3
), LatestEdits as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6,10,11)
    group by ph.PostId
), RankedPosts as (
    select
        rup.UserId,
        rup.DisplayName,
        rup.PostId,
        rup.PostTypeId,
        rup.Score,
        rup.ViewCount,
        rup.CreationDate,
        le.LastEditDate,
        row_number() over (partition by rup.UserId order by rup.Score desc, rup.ViewCount desc) as rn
    from RecursiveUserPosts rup
    left join LatestEdits le on le.PostId = rup.PostId
    where rup.Score >= (
        select avg(p2.Score) from Posts p2
        where p2.PostTypeId = rup.PostTypeId
        and (p2.OwnerUserId = rup.UserId or p2.OwnerUserId is null)
    )
), UserBadgeCounts as (
    select
        u.Id as UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
), TopTagsPerUser as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag,
        count(*) as TagCount,
        row_number() over (partition by p.OwnerUserId order by count(*) desc) as TagRank
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and p.OwnerUserId > 0
    group by p.OwnerUserId, Tag
), LatestCommentsWithUser as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Score as CommentScore,
        c.CreationDate as CommentDate,
        c.Text as CommentText,
        u.DisplayName as CommentUserDisplayName,
        c.UserId
    from Comments c
    left join Users u on u.Id = c.UserId
    order by c.PostId, c.CreationDate desc
)
select 
    rp.UserId,
    rp.DisplayName,
    rp.PostId,
    pt.Name as PostType,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.LastEditDate,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    coalesce(tt.Tag, 'N/A') as TopTag,
    coalesce(tt.TagCount, 0) as TopTagCount,
    lc.CommentId,
    lc.CommentScore,
    substring(lc.CommentText from 1 for 50) || case when length(lc.CommentText) > 50 then '...' else '' end as CommentSnippet,
    case 
        when rp.ViewCount > 10000 then 'Hot'
        when rp.ViewCount between 1000 and 10000 then 'Warm'
        else 'Cold'
    end as PopularityCategory,
    case 
        when ub.GoldBadges >= 3 then 'Elite'
        when ub.SilverBadges >= 5 then 'Experienced'
        when ub.BronzeBadges >= 10 then 'Active'
        else 'Newbie'
    end as UserTier,
    (select count(*) from PostLinks pl where pl.PostId = rp.PostId and pl.LinkTypeId = 3) as DuplicateCount,
    (select count(*) from Votes v where v.PostId = rp.PostId and v.VoteTypeId = 2) as UpVotes,
    (select count(*) from Votes v where v.PostId = rp.PostId and v.VoteTypeId = 3) as DownVotes,
    abs(rp.Score + coalesce(lc.CommentScore,0) - 0.5 * rp.ViewCount) as CustomRankingScore
from RankedPosts rp
join PostTypes pt on pt.Id = rp.PostTypeId
left join UserBadgeCounts ub on ub.UserId = rp.UserId
left join TopTagsPerUser tt on tt.UserId = rp.UserId and tt.TagRank = 1
left join LatestCommentsWithUser lc on lc.PostId = rp.PostId
where rp.rn <= 5
and (rp.Score + coalesce(lc.CommentScore,0)) / nullif(rp.ViewCount,1) > 0.01
union
select 
    u.Id as UserId,
    u.DisplayName,
    p.Id as PostId,
    pt.Name as PostType,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    null as LastEditDate,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    'N/A' as TopTag,
    0 as TopTagCount,
    null as CommentId,
    null as CommentScore,
    null as CommentSnippet,
    'Cold' as PopularityCategory,
    'Newbie' as UserTier,
    0 as DuplicateCount,
    0 as UpVotes,
    0 as DownVotes,
    p.Score as CustomRankingScore
from Users u
cross join lateral (
    select p2.*
    from Posts p2
    join PostTypes pt2 on pt2.Id = p2.PostTypeId
    where p2.OwnerUserId = u.Id and p2.PostTypeId = 1
    order by p2.CreationDate desc
    limit 1
) p
join PostTypes pt on pt.Id = p.PostTypeId
where u.Reputation < 100 
except
select 
    rp.UserId,
    rp.DisplayName,
    rp.PostId,
    pt.Name as PostType,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.LastEditDate,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    coalesce(tt.Tag, 'N/A') as TopTag,
    coalesce(tt.TagCount, 0) as TopTagCount,
    lc.CommentId,
    lc.CommentScore,
    substring(lc.CommentText from 1 for 50) || case when length(lc.CommentText) > 50 then '...' else '' end as CommentSnippet,
    case 
        when rp.ViewCount > 10000 then 'Hot'
        when rp.ViewCount between 1000 and 10000 then 'Warm'
        else 'Cold'
    end as PopularityCategory,
    case 
        when ub.GoldBadges >= 3 then 'Elite'
        when ub.SilverBadges >= 5 then 'Experienced'
        when ub.BronzeBadges >= 10 then 'Active'
        else 'Newbie'
    end as UserTier,
    (select count(*) from PostLinks pl where pl.PostId = rp.PostId and pl.LinkTypeId = 3) as DuplicateCount,
    (select count(*) from Votes v where v.PostId = rp.PostId and v.VoteTypeId = 2) as UpVotes,
    (select count(*) from Votes v where v.PostId = rp.PostId and v.VoteTypeId = 3) as DownVotes,
    abs(rp.Score + coalesce(lc.CommentScore,0) - 0.5 * rp.ViewCount) as CustomRankingScore
from RankedPosts rp
join PostTypes pt on pt.Id = rp.PostTypeId
left join UserBadgeCounts ub on ub.UserId = rp.UserId
left join TopTagsPerUser tt on tt.UserId = rp.UserId and tt.TagRank = 1
left join LatestCommentsWithUser lc on lc.PostId = rp.PostId
where rp.rn <= 5
and (rp.Score + coalesce(lc.CommentScore,0)) / nullif(rp.ViewCount,1) > 0.01
order by UserId, CustomRankingScore desc
limit 100;