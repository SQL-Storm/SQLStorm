-- {"query": "2699.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1360} 
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc nulls last) as OwnerPostRank,
        count(*) over (partition by p.OwnerUserId) as OwnerTotalPosts,
        case 
            when p.Tags is not null then array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'), 1)
            else 0
        end as TagCount
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId,b.Class
),
UserScoreSum as (
    select
        OwnerUserId,
        sum(Score) as TotalScore,
        max(Score) as MaxScore,
        avg(Score) as AvgScore
    from Posts
    where OwnerUserId is not null
    group by OwnerUserId
),
PostCommentsCount as (
    select 
        c.PostId,
        count(c.Id) as CommentCount
    from Comments c
    group by c.PostId
),
DuplicateLinks as (
    select 
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    group by pl.PostId
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
),
CloseReasonNames as (
    select 
        crt.Id, crt.Name 
    from CloseReasonTypes crt
),
PostWithDetails as (
    select
        rp.Id,
        rp.PostTypeId,
        rp.Title,
        rp.OwnerUserId,
        rp.OwnerName,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.TagCount,
        coalesce(ubc.Class, 0) as BadgeClass,
        coalesce(ubc.BadgeCount, 0) as BadgeCount,
        coalesce(usc.TotalScore, 0) as UserTotalScore,
        coalesce(usc.MaxScore, 0) as UserMaxScore,
        coalesce(usc.AvgScore, 0) as UserAvgScore,
        coalesce(pc.CommentCount, 0) as PostCommentCount,
        coalesce(dl.DuplicateCount, 0) as PostDuplicateCount,
        cr.Name as CloseReasonName,
        case 
            when rp.Tags ilike '%<sql>%' then 'Contains SQL Tag'
            else 'No SQL Tag'
        end as SqlTagPresence
    from RankedPosts rp
    left join UserBadgeCounts ubc on ubc.UserId = rp.OwnerUserId and ubc.Class = 1  -- Gold badges only
    left join UserScoreSum usc on usc.OwnerUserId = rp.OwnerUserId
    left join PostCommentsCount pc on pc.PostId = rp.Id
    left join DuplicateLinks dl on dl.PostId = rp.Id
    left join PostHistoryCloseReasons phcr on phcr.PostId = rp.Id
    left join CloseReasonNames cr on cr.Id = phcr.CloseReasonId
),
FilteredPosts as (
    select *
    from PostWithDetails
    where 
        (BadgeCount > 0 or UserTotalScore > 1000)
        and (CloseReasonName is null or CloseReasonName not in ('Duplicate', 'Off-topic'))
),
FinalRanked as (
    select
        fp.*,
        rank() over (
            partition by fp.OwnerUserId 
            order by fp.Score desc nulls last, fp.ViewCount desc nulls last, fp.CreationDate desc nulls last
        ) as UserPostRankScore,
        dense_rank() over (
            order by case when fp.SqlTagPresence = 'Contains SQL Tag' then 0 else 1 end, fp.Score desc nulls last
        ) as GlobalSqlTagRank
    from FilteredPosts fp
)
select
    fr.OwnerUserId,
    fr.OwnerName,
    fr.Id as PostId,
    fr.PostTypeId,
    fr.Title,
    fr.Score,
    fr.ViewCount,
    fr.CreationDate,
    fr.TagCount,
    fr.BadgeCount as GoldBadges,
    fr.UserTotalScore,
    fr.UserMaxScore,
    fr.UserAvgScore,
    fr.PostCommentCount,
    fr.PostDuplicateCount,
    fr.CloseReasonName,
    fr.SqlTagPresence,
    fr.UserPostRankScore,
    fr.GlobalSqlTagRank,
    -- Complex string expression: concatenate Title reversed, OwnerName upper case, and TagCount padded left
    concat(
        reverse(coalesce(fr.Title, '')),
        ' / ',
        upper(coalesce(fr.OwnerName, 'UNKNOWN')),
        ' / ',
        lpad(cast(fr.TagCount as text), 3, '0')
    ) as ComplexStringField,
    -- Derived metric with NULL logic and CASE expressions
    case 
        when fr.Score is null or fr.Score <= 0 then null
        when fr.Score > 100 then fr.Score * 1.1
        else fr.Score * 0.9
    end as AdjustedScore,
    -- Correlated subquery for count of answers to question if post is a question
    (select count(1) from Posts ans where ans.ParentId = fr.Id and ans.PostTypeId = 2) as AnswerCount,
    -- Set operation simulation: union for posts with or without duplicates
    (select 'HasDuplicates' where fr.PostDuplicateCount > 0
     union
     select 'NoDuplicates' where fr.PostDuplicateCount = 0
    ) as DuplicateStatus
from FinalRanked fr
where fr.UserPostRankScore <= 5
order by fr.GlobalSqlTagRank, fr.Score desc nulls last, fr.CreationDate desc nulls last
limit 100;