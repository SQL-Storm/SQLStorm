-- {"query": "2441.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1607}
with recursive RecursiveUserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        cast(count(*) as integer) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation, b.Class

    union all

    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        case when r.Class = 1 then 2
             when r.Class = 2 then 3
             when r.Class = 3 then 1
             else 1 end as Class,
        cast(r.BadgeCount + 1 as integer) as BadgeCount
    from RecursiveUserBadgeCounts r
    where r.BadgeCount < 3
),
LatestPosts as (
    select
        p.OwnerUserId,
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
),
UserTagAggregation as (
    select
        p.OwnerUserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag
    from Posts p
    where p.Tags is not null and p.Tags <> ''
),
UserTopTags as (
    select
        OwnerUserId,
        Tag,
        count(*) as TagCount,
        rank() over (partition by OwnerUserId order by count(*) desc) as TagRank
    from UserTagAggregation
    group by OwnerUserId, Tag
),
FilteredTopTags as (
    select OwnerUserId, Tag, TagCount from UserTopTags where TagRank <= 3
),
PostLinkDupCount as (
    select
        pl.PostId,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateLinkCount
    from PostLinks pl
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
PostCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as LastClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as LastReopenedDate,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as integer) else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
),
CloseReasonNames as (
    select * from CloseReasonTypes
),
UserActivityWindow as (
    select
        u.Id as UserId,
        count(p.Id) filter (where p.CreationDate >= (cast('2024-10-01' as date) - interval '30 days')) as PostsLast30Days,
        count(c.Id) filter (where c.CreationDate >= (cast('2024-10-01' as date) - interval '30 days')) as CommentsLast30Days
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    group by u.Id
),
UserPostScores as (
    select
        p.OwnerUserId,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        min(p.Score) as MinPostScore,
        count(*) as TotalPosts
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
    group by p.OwnerUserId
),
AnswerAcceptanceRates as (
    select
        q.OwnerUserId,
        count(a.Id) as AnswerCount,
        count(a.Id) filter (where q.AcceptedAnswerId = a.Id) as AcceptedAnswers,
        case when count(a.Id) = 0 then 0
             else 1.0 * count(a.Id) filter (where q.AcceptedAnswerId = a.Id) / count(a.Id) end as AcceptanceRate
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.OwnerUserId is not null and q.OwnerUserId > 0
    group by q.OwnerUserId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    r.BadgeCount,
    r.Class as BadgeClass,
    coalesce(ups.AvgPostScore,0) as AveragePostScore,
    coalesce(ups.MaxPostScore,0) as MaxPostScore,
    coalesce(ups.MinPostScore,0) as MinPostScore,
    coalesce(aas.AnswerCount,0) as TotalAnswers,
    coalesce(aas.AcceptedAnswers,0) as AcceptedAnswers,
    round(coalesce(aas.AcceptanceRate,0),2) as AcceptanceRate,
    ua.PostsLast30Days,
    ua.CommentsLast30Days,
    string_agg(distinct ftt.Tag, ', ') as TopTags,
    lp.Id as LatestPostId,
    lp.Title as LatestPostTitle,
    lp.Score as LatestPostScore,
    pl.DuplicateLinkCount,
    cr.Name as LastCloseReason,
    case 
        when pc.LastClosedDate is not null 
          and (pc.LastReopenedDate is null or pc.LastReopenedDate < pc.LastClosedDate) 
        then true 
        else false 
    end as CurrentlyClosed
from Users u
left join (
    select UserId, max(BadgeCount) as MaxBadgeCount
    from RecursiveUserBadgeCounts
    group by UserId
) rmax on u.Id = rmax.UserId
left join RecursiveUserBadgeCounts r on r.UserId = u.Id and r.BadgeCount = rmax.MaxBadgeCount
left join UserPostScores ups on u.Id = ups.OwnerUserId
left join AnswerAcceptanceRates aas on u.Id = aas.OwnerUserId
left join UserActivityWindow ua on u.Id = ua.UserId
left join FilteredTopTags ftt on u.Id = ftt.OwnerUserId
left join LatestPosts lp on u.Id = lp.OwnerUserId and lp.rn = 1
left join PostLinkDupCount pl on lp.Id = pl.PostId
left join PostCloseInfo pc on lp.Id = pc.PostId
left join CloseReasonNames cr on pc.CloseReasonId = cr.Id
where u.Reputation > 1000
  and (lp.CreationDate > (cast('2024-10-01' as date) - interval '180 days') or lp.CreationDate is null)
  and (ua.PostsLast30Days > 0 or ua.CommentsLast30Days > 0)
  and (r.Class in (1,2))
group by 
    u.Id, u.DisplayName, u.Reputation, r.BadgeCount, r.Class,
    ups.AvgPostScore, ups.MaxPostScore, ups.MinPostScore,
    aas.AnswerCount, aas.AcceptedAnswers, aas.AcceptanceRate,
    ua.PostsLast30Days, ua.CommentsLast30Days,
    lp.Id, lp.Title, lp.Score,
    pl.DuplicateLinkCount,
    cr.Name,
    pc.LastClosedDate, pc.LastReopenedDate
order by AcceptanceRate desc, AveragePostScore desc, PostsLast30Days desc
limit 50;