-- {"query": "2113.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1680} 
with RecursiveCTE as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        1 as Level,
        cast(p.Tags as varchar(4000)) as AggregatedTags
    from Posts p
    where p.PostTypeId = 1
    and p.Tags is not null
    union all
    select 
        c.PostId,
        p2.PostTypeId,
        p2.OwnerUserId,
        p2.Title,
        p2.Score,
        p2.ViewCount,
        p2.Tags,
        p2.CreationDate,
        r.Level + 1,
        r.AggregatedTags || '|' || coalesce(p2.Tags,'') 
    from RecursiveCTE r
    join Posts p2 on p2.ParentId = r.Id
    join Comments c on c.PostId = p2.Id
    where r.Level < 3
),
UserBadgeAgg as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreStats as (
    select 
        OwnerUserId,
        avg(Score) over (partition by OwnerUserId) as AvgScore,
        max(Score) over (partition by OwnerUserId) as MaxScore,
        min(Score) over (partition by OwnerUserId) as MinScore,
        count(*) over (partition by OwnerUserId) as PostCount
    from Posts p
    where p.OwnerUserId is not null
),
TaggedPosts as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        u.Id as OwnerUserId,
        u.DisplayName,
        u.Reputation,
        string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') as TagArray
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Tags is not null
),
ExplodedTags as (
    select
        tp.Id as PostId,
        unnest(tp.TagArray) as Tag,
        tp.Score,
        tp.CreationDate,
        tp.OwnerUserId,
        tp.DisplayName,
        tp.Reputation
    from TaggedPosts tp
),
RankedPosts as (
    select
        et.*,
        row_number() over (partition by et.OwnerUserId order by et.Score desc, et.CreationDate desc) as UserTagRank
    from ExplodedTags et
),
HighRankPosts as (
    select * from RankedPosts where UserTagRank <= 5
),
LinkedDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate as LinkCreated,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),
AggregatedComments as (
    select
        c.PostId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(coalesce(c.UserDisplayName,'[deleted]'), ', ' order by c.CreationDate desc) as CommentUsers
    from Comments c
    group by c.PostId
),
PostHistoryCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenedDate,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as ClosedCount,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenedCount
    from PostHistory ph
    group by ph.PostId
)

select 
    p.Id as QuestionId,
    p.Title,
    u.DisplayName as OwnerName,
    u.Reputation,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ps.AvgScore,
    ps.MaxScore,
    ps.MinScore,
    ps.PostCount,
    ac.CommentCount,
    ac.LastCommentDate,
    ac.CommentUsers,
    phc.LastClosedDate,
    phc.LastReopenedDate,
    phc.ClosedCount,
    phc.ReopenedCount,
    ld.CountOfDuplicates,
    string_agg(distinct lt.Name, ',' order by lt.Name) filter (where lt.Name is not null) as LinkedTypes,
    max(r.Level) as MaxRecursionLevel,
    array_agg(distinct rt.Tag) filter (where rt.Tag is not null) as UniqueTags,
    concat_ws(' / ', 
        coalesce(nullif(p.Title,''),'[No Title]'), 
        coalesce(u.DisplayName, '[Anon]'), 
        coalesce(cast(ps.AvgScore as varchar), '0'), 
        coalesce(cast(ub.BadgeCount as varchar), '0')) as CompositeSignature,
    case 
        when p.ClosedDate is not null then 'Closed'
        when p.AcceptedAnswerId is not null then 'Answered'
        else 'Open'
    end as Status,
    case 
        when p.ViewCount > 100000 then 'Highly Viewed'
        when p.ViewCount between 10000 and 100000 then 'Moderately Viewed'
        else 'Low Viewed'
    end as ViewCategory
from Posts p
left join Users u on u.Id = p.OwnerUserId
left join UserBadgeAgg ub on ub.UserId = u.Id
left join PostScoreStats ps on ps.OwnerUserId = u.Id
left join AggregatedComments ac on ac.PostId = p.Id
left join PostHistoryCloseInfo phc on phc.PostId = p.Id
left join (
    select 
        PostId,
        count(*) as CountOfDuplicates
    from LinkedDuplicates
    group by PostId
) ld on ld.PostId = p.Id
left join PostLinks pl on pl.PostId = p.Id
left join LinkTypes lt on lt.Id = pl.LinkTypeId
left join RecursiveCTE r on r.Id = p.Id
left join RankedPosts rt on rt.PostId = p.Id
where p.PostTypeId = 1
group by 
    p.Id, p.Title, u.DisplayName, u.Reputation, ub.BadgeCount, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, 
    ps.AvgScore, ps.MaxScore, ps.MinScore, ps.PostCount, ac.CommentCount, ac.LastCommentDate, ac.CommentUsers,
    phc.LastClosedDate, phc.LastReopenedDate, phc.ClosedCount, phc.ReopenedCount, ld.CountOfDuplicates, p.ClosedDate, p.AcceptedAnswerId, p.ViewCount
order by 
    ps.AvgScore desc nulls last, 
    ps.PostCount desc nulls last, 
    p.ViewCount desc nulls last
limit 100;