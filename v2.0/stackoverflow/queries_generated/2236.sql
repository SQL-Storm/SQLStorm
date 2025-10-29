-- {"query": "2236.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1155} 
with UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter(where b.Class = 1) as GoldBadges,
        count(b.Id) filter(where b.Class = 2) as SilverBadges,
        count(b.Id) filter(where b.Class = 3) as BronzeBadges,
        row_number() over(partition by u.Id order by max(b.Date) desc) as LastBadgeRank
    from 
        Users u
        left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
TopScoringPosts as (
    select 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.PostTypeId,
        p.Title,
        coalesce(p.Tags, '') as Tags,
        u.DisplayName as OwnerDisplayName,
        rank() over(partition by p.PostTypeId order by p.Score desc) as ScoreRank
    from 
        Posts p
        left join Users u on p.OwnerUserId = u.Id
    where 
        p.Score > 50 and
        p.PostTypeId in (1,2)
),
PostDetailsCTE as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce((select count(*) from Comments c where c.PostId = p.Id), 0) as CommentCount,
        coalesce((select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2),0) as UpvotesCount,
        coalesce((select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3),0) as DownvotesCount,
        case 
            when p.AcceptedAnswerId is not null then 1 
            else 0 
        end as HasAcceptedAnswer,
        (
            select top 1 pht.Name from PostHistory ph
            join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
            where ph.PostId = p.Id
            order by ph.CreationDate desc
        ) as LastHistoryTypeName
    from 
        Posts p
        left join Users u on p.OwnerUserId = u.Id
    where 
        p.PostTypeId = 1 and p.ClosedDate is null
),
DuplicatesCTE as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from
        PostLinks pl
    where 
        pl.LinkTypeId = 3 -- duplicates
    group by pl.PostId
),
QuestionRanks as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (partition by date_trunc('month', p.CreationDate) order by p.Score desc, p.ViewCount desc) as MonthlyRank
    from 
        Posts p
        left join Users u on p.OwnerUserId = u.Id
    where 
        p.PostTypeId = 1
), 
BadgeSummary as (
    select
        b.UserId,
        array_agg(distinct b.Name) over (partition by b.UserId) as BadgeNames,
        count(*) over (partition by b.UserId) as BadgeCount
    from Badges b
)
select
    q.QuestionId,
    q.Title,
    q.Score,
    q.ViewCount,
    length(q.Tags) - length(replace(q.Tags, '><', '')) + 1 as TagCount,
    q.OwnerName,
    coalesce(d.DuplicateCount, 0) as DuplicateCount,
    pdc.CommentCount,
    pdc.UpvotesCount,
    pdc.DownvotesCount,
    pdc.HasAcceptedAnswer,
    pdc.LastHistoryTypeName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    bs.BadgeCount,
    case when q.MonthlyRank <= 10 then 'Top 10' else 'Other' end as PopularityCategory,
    concat(
        left(coalesce(q.Title, ''), 30),
        case when length(coalesce(q.Title, '')) > 30 then '...' else '' end
    ) as ShortTitle,
    case 
        when q.ViewCount > 10000 and q.Score > 100 then 'Hot Question'
        when q.ViewCount > 5000 then 'Warm Question'
        else 'Normal Question' 
    end as QuestionHeatStatus
from
    QuestionRanks q
    left join DuplicatesCTE d on q.QuestionId = d.PostId
    left join PostDetailsCTE pdc on q.QuestionId = pdc.Id
    left join UserBadgeCounts ubc on q.OwnerUserId = ubc.UserId
    left join BadgeSummary bs on q.OwnerUserId = bs.UserId
where
    (q.Score > 75 or q.ViewCount > 8000)
    and (ubc.GoldBadges + ubc.SilverBadges + ubc.BronzeBadges) > 0
order by
    q.CreationDate desc,
    q.Score desc,
    q.ViewCount desc
limit 100;