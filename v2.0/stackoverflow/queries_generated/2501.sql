-- {"query": "2501.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1269} 
with UserStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) as LastBadgeAwarded,
        row_number() over (order by u.Reputation desc, u.Id) as RankByReputation
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
), QuestionAnswerStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        count(distinct a.Id) filter (where a.PostTypeId = 2) as AnswerCount,
        max(a.Score) filter (where a.PostTypeId = 2) as MaxAnswerScore,
        -- Correlated subquery to count comments on this post
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        -- Window function: running total of scores per user ordered by date
        sum(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between unbounded preceding and current row) as RunningScore,
        -- string expression: concatenation of tags into a single string (if tags exist)
        case when p.Tags is not null and p.Tags <> '' then p.Tags else '<no-tags>' end as EffectiveTags
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags
), CloseReasonCount as (
    select 
        cht.Name as CloseReasonName,
        count(distinct ph.PostId) as ClosedPostsCount
    from PostHistory ph
    join PostHistoryTypes chtt on ph.PostHistoryTypeId = chtt.Id
    join CloseReasonTypes cht on cast(ph.Comment as int) = cht.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by cht.Name
), DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate link type
), DuplicateStats as (
    select
        p.Id as QuestionId,
        p.Title,
        count(distinct dl.RelatedPostId) as DuplicateCount
    from Posts p
    left join DuplicateLinks dl on dl.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title
), ComplexPosts as (
    select 
        qas.PostId,
        qas.Title,
        qas.Score,
        us.DisplayName as OwnerName,
        us.Reputation,
        qas.ViewCount,
        qas.AnswerCount,
        qas.MaxAnswerScore,
        qas.CommentCount,
        qas.RunningScore,
        qas.EffectiveTags,
        ds.DuplicateCount,
        crc.ClosedPostsCount as TotalClosedPostsForReason
    from QuestionAnswerStats qas
    left join Users us on us.Id = qas.OwnerUserId
    left join DuplicateStats ds on ds.QuestionId = qas.PostId
    left join CloseReasonCount crc on crc.CloseReasonName = 'Duplicate'
    where qas.AnswerCount > 0
), RankedComplexPosts as (
    select *,
    rank() over (partition by OwnerName order by Score desc, AnswerCount desc) as RankPerUser,
    dense_rank() over (order by DuplicationRank) as GlobalDuplicateRank
    from (
        select cp.*,
            row_number() over (order by ds.DuplicateCount desc nulls last) as DuplicationRank
        from ComplexPosts cp
        left join DuplicateStats ds on ds.QuestionId = cp.PostId
    ) sub
)
select 
    rcp.PostId,
    coalesce(rcp.Title, '<untitled>') as Title,
    rcp.Score,
    rcp.ViewCount,
    rcp.AnswerCount,
    rcp.MaxAnswerScore,
    rcp.CommentCount,
    rcp.RunningScore,
    rcp.EffectiveTags,
    rcp.DuplicateCount,
    rcp.OwnerName,
    rcp.Reputation,
    rcp.RankPerUser,
    rcp.GlobalDuplicateRank,
    coalesce(rcp.TotalClosedPostsForReason, 0) as TotalClosedDuplicates,
    -- Complex predicate including NULL logic and string manipulation
    case 
        when rcp.DuplicateCount is null or rcp.DuplicateCount = 0 then 'Unique Question'
        when rcp.DuplicateCount > 5 and rcp.Score > 10 then concat('Highly Duplicated & Popular with Score ', rcp.Score)
        when rcp.DuplicateCount > 0 then 'Duplicated Question'
        else 'Unknown Status'
    end as QuestionStatus,
    -- Conditional aggregation with EXISTS (correlated subquery)
    case 
        when exists (
            select 1 
            from Votes v 
            where v.PostId = rcp.PostId and v.VoteTypeId = 4 -- Offensive vote
            limit 1
        ) then 'Flagged as Offensive'
        else 'Clean'
    end as ModerationStatus
from RankedComplexPosts rcp
where rcp.Reputation > 1000 and rcp.RankPerUser <= 5
order by rcp.Reputation desc, rcp.Score desc, rcp.AnswerCount desc;