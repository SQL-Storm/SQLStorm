-- {"query": "2617.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1296} 
with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by b.Date desc nulls last) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopUsers as (
    select UserId, DisplayName, GoldBadges, SilverBadges, BronzeBadges
    from UserBadgeCounts
    where rn = 1
    order by GoldBadges desc, SilverBadges desc, BronzeBadges desc
    limit 10
),
PostScoreWindow as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Title,
        sum(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between unbounded preceding and current row) as RunningScore,
        rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2)
),
Duplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalQuestion,
        p2.Title as DuplicateQuestion
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
LatestCloseInfo as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    order by ph.PostId, ph.CreationDate desc
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as TotalClosuresInitiated,
        max(p.CreationDate) filter (where p.OwnerUserId = u.Id) as LastPostDate,
        max(c.CreationDate) filter (where c.UserId = u.Id) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName
)
select 
    tu.DisplayName as TopUser,
    tu.GoldBadges, 
    tu.SilverBadges, 
    tu.BronzeBadges,
    pa.TotalPosts,
    pa.TotalComments,
    pa.TotalClosuresInitiated,
    coalesce(lci.CloseDate::date, 'N/A') as LastClosedDate,
    coalesce(lci.CloseReason, 'N/A') as LastCloseReason,
    ds.DuplicateQuestion,
    ds.OriginalQuestion,
    psw.Id as PostId,
    psw.Title,
    psw.Score,
    psw.RunningScore,
    psw.ScoreRank,
    case 
        when psw.Score > 10 then 'Popular'
        when psw.Score > 0 then 'Normal'
        else 'Low'
    end as PopularityCategory,
    -- complicated string logic: concatenate tags if question, else empty
    case when psw.PostTypeId = 1 then
        coalesce(
            (select 
                string_agg(trim(tag), ',' order by tag)
             from unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as tag
            ), '')
        else ''
    end as Tags,
    -- Example of correlated subquery with NULL logic: number of comments on each post excluding deleted comments (simulated by score >= 0)
    (select count(*) from Comments c where c.PostId = psw.Id and (c.Score >= 0 or c.Score is null)) as ValidCommentCount
from TopUsers tu
left join UserActivity pa on pa.Id = tu.UserId
left join LatestCloseInfo lci on lci.PostId = (
    select p.Id from Posts p where p.OwnerUserId = tu.UserId order by p.CreationDate desc limit 1
)
left join Duplicates ds on ds.PostId = (
    select p.Id from Posts p where p.OwnerUserId = tu.UserId and p.PostTypeId = 1 order by p.CreationDate desc limit 1
)
left join PostScoreWindow psw on psw.OwnerUserId = tu.UserId
where psw.ScoreRank <= 3
union
select 
    'Anonymous' as TopUser,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as TotalPosts,
    0 as TotalComments,
    0 as TotalClosuresInitiated,
    'N/A' as LastClosedDate,
    'N/A' as LastCloseReason,
    null as DuplicateQuestion,
    null as OriginalQuestion,
    p.Id as PostId,
    p.Title,
    p.Score,
    0 as RunningScore,
    0 as ScoreRank,
    'Unknown' as PopularityCategory,
    '' as Tags,
    0 as ValidCommentCount
from Posts p
where p.OwnerUserId is null or p.OwnerUserId = -1
order by GoldBadges desc nulls last, Score desc nulls last, PostId
limit 50;