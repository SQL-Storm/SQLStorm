-- {"query": "2786.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1160} 
with RecursivePosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        coalesce(p.Tags, '') as Tags,
        1 as Depth,
        array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 -- questions
    
    union all
    
    select 
        c.Id,
        c.PostTypeId,
        c.ParentId,
        c.Score,
        c.ViewCount,
        c.OwnerUserId,
        c.CreationDate,
        c.Title,
        coalesce(c.Tags, '') as Tags,
        rp.Depth + 1,
        rp.Path || c.Id
    from Posts c
    join RecursivePosts rp on c.ParentId = rp.Id
    where c.PostTypeId in (2, 7) -- answers or wiki placeholder
),
UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = true then 1 else 0 end) as TagBasedBadges,
        u.Reputation
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostMaxScoreRanks as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2)
),
TopUserPosts as (
    select 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags
    from Posts p
    join PostMaxScoreRanks pm on pm.Id = p.Id and pm.ScoreRank = 1
),
ClosedQuestionsWithReason as (
    select
        ph.PostId,
        p.Title,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
RecentCommentStats as (
    select 
        c.PostId,
        count(c.Id) as RecentCommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.CreationDate > now() - interval '30 days'
    group by c.PostId
)
select 
    rp.Id as PostId,
    rp.Title,
    rp.PostTypeId,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.Depth,
    array_to_string(rp.Path, '->') as PostHierarchyPath,
    
    ub.DisplayName as OwnerName,
    ub.Reputation as OwnerReputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    
    tc.Score as TopUserPostScore,
    tc.ViewCount as TopUserPostViews,
    tc.Title as TopUserPostTitle,
    
    coalesce(cq.CloseReason, 'Open') as CloseStatus,
    cq.CloseDate,
    cq.CloserUserName,
    
    rc.RecentCommentCount,
    rc.LastCommentDate,
    
    -- Complex calculations and predicates
    case 
        when rp.Score > 0 then log(rp.Score + 1)
        else 0
    end as ScoreLog,
    
    length(coalesce(rp.Title, '')) as TitleLength,
    
    case
        when rp.Tags = '' then 'NoTags'
        else substring(rp.Tags from 2 for char_length(rp.Tags) - 2)
    end as TagsTrimmed,
    
    -- Window function: rank posts by Score within same Owner
    rank() over (partition by rp.OwnerUserId order by rp.Score desc nulls last) as OwnerScoreRank,
    
    -- String expressions with NULL logic and conditional replacement
    coalesce(nullif(rp.Title, ''), 'No Title') || ' [Score:' || coalesce(cast(rp.Score as varchar), '0') || ']' as DisplayTitle
    
from RecursivePosts rp
left join UserBadgeCounts ub on ub.UserId = rp.OwnerUserId
left join TopUserPosts tc on tc.OwnerUserId = rp.OwnerUserId
left join ClosedQuestionsWithReason cq on cq.PostId = rp.Id
left join RecentCommentStats rc on rc.PostId = rp.Id
where rp.Depth <= 3
  and (
    rp.Score is not null and rp.Score >= 0
    or rp.ViewCount > 1000
  )
order by 
    ub.Reputation desc nulls last,
    rp.Score desc nulls last,
    rp.CreationDate desc
limit 100;