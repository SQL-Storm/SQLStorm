-- {"query": "1154.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1194} 
with RecursiveCTE as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName as OwnerName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn,
        ARRAY[coalesce(p.Id,0)] as Visited
    from 
        Posts p
        left join Users u on p.OwnerUserId = u.Id
        left join Badges b on u.Id = b.UserId
    where p.PostTypeId in (1,2) and p.CreationDate > '2022-01-01'
    union all
    select
        pl.RelatedPostId as Id,
        p2.PostTypeId,
        p2.Title,
        p2.Score,
        p2.ViewCount,
        p2.CreationDate,
        u2.DisplayName as OwnerName,
        u2.Reputation,
        count(b2.Id) filter (where b2.Class = 1),
        count(b2.Id) filter (where b2.Class = 2),
        count(b2.Id) filter (where b2.Class = 3),
        cte.rn + 1,
        cte.Visited || pl.RelatedPostId
    from
        RecursiveCTE cte
        join PostLinks pl on cte.Id = pl.PostId and pl.LinkTypeId in (1,3)
        join Posts p2 on pl.RelatedPostId = p2.Id
        left join Users u2 on p2.OwnerUserId = u2.Id
        left join Badges b2 on u2.Id = b2.UserId
    where
        not pl.RelatedPostId = any(cte.Visited)
        and cte.rn < 5
),
CloseVotesCTE as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as LatestCloseReasonId,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastClosedDate
    from PostHistory ph
    group by ph.PostId
),
ScoreStats as (
    select 
        p.Id,
        p.Score,
        avg(vt.Score) over () as AverageVoteScore,
        case when p.Score > avg(p.Score) over () then 'AboveAvg' else 'BelowAvg' end as ScoreCategory,
        coalesce(cvc.CloseVotesCount,0) as CloseVotes,
        coalesce(cvc.LatestCloseReasonId,0) as CloseReasonId,
        cvc.LastClosedDate
    from Posts p
    left join (
        select VoteTypeId, PostId, count(*) as Score
        from Votes
        where VoteTypeId in (2,3)
        group by VoteTypeId, PostId
    ) vt on p.Id = vt.PostId
    left join CloseVotesCTE cvc on p.Id = cvc.PostId
)
select 
    c.Id,
    c.Title,
    c.Score,
    c.ViewCount,
    c.CreationDate,
    c.OwnerName,
    concat_ws(' | ',
        cast(c.GoldBadges as varchar), 'Gold',
        cast(c.SilverBadges as varchar), 'Silver',
        cast(c.BronzeBadges as varchar), 'Bronze') as BadgeSummary,
    ss.AverageVoteScore,
    ss.ScoreCategory,
    ss.CloseVotes,
    crt.Name as CloseReason,
    ROW_NUMBER() OVER (PARTITION BY c.PostTypeId ORDER BY c.Score DESC) as Rank,
    case
        when c.Score > 100 and c.ViewCount > 1000 then 'Popular and Highly Rated'
        when c.Score < 0 or c.ViewCount < 100 then 'Low Engagement'
        else 'Normal'
    end as EngagementCategory,
    substring(p.Body from 1 for 150) as ExcerptBody,
    (select string_agg(u2.DisplayName, ', ') from Users u2 where u2.Reputation > 100000 and u2.Id in (
        select distinct OwnerUserId from Posts p3 where p3.Tags like concat('%', t.TagName, '%')
    )) as HighRepUsersForTag,
    array_length(string_to_array(ts.TagName, ''),1) as TagNameCharCount
from RecursiveCTE c
join ScoreStats ss on c.Id = ss.Id
left join CloseReasonTypes crt on crt.Id = ss.CloseReasonId
left join Posts p on p.Id = c.Id and p.PostTypeId = 1
left join Tags t on t.TagName = any(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))
left join Tags ts on ts.Id = (
    select TagId from (
        select Tags.Id as TagId, row_number() over (order by Tags.Count desc) as rnk
        from Tags
        where Tags.TagName = any(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))
    ) tt where rnk = 1
)
where c.rn = 1
order by c.Score desc
limit 25;