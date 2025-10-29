-- {"query": "2049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1414} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadgeCount,
        count(b.Id) filter (where b.Class = 2) as SilverBadgeCount,
        count(b.Id) filter (where b.Class = 3) as BronzeBadgeCount,
        row_number() over (partition by u.Id order by b.Date desc nulls last) as LatestBadgeRank,
        max(b.Date) as LatestBadgeDate
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
), RecentPostActivity as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc nulls last) as PostScoreRank,
        count(c.Id) over (partition by p.Id) as CommentCount,
        coalesce((
            select max(v.CreationDate) 
            from Votes v 
            where v.PostId = p.Id and v.VoteTypeId = 2
        ), p.CreationDate) as LastUpvoteDate
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1,2) -- questions and answers
), ClosedQuestionDetails as (
    select
        ph.PostId,
        min(ph.CreationDate) as FirstCloseDate,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseCount,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenCount,
        string_agg(distinct crt.Name, ', ') as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
), UserTagAggregates as (
    select
        u.Id as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag,
        count(*) as TagPostCount,
        avg(p.Score) as AvgTagPostScore
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    group by u.Id, Tag
), UserTagRank as (
    select
        *,
        rank() over (partition by UserId order by TagPostCount desc, AvgTagPostScore desc) as TagRank
    from UserTagAggregates
), TopUserTags as (
    select UserId, Tag, TagPostCount, AvgTagPostScore
    from UserTagRank
    where TagRank <= 3
), HighActivityUsers as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(sum(rpa.Score),0) as TotalPostScore,
        coalesce(sum(rpa.ViewCount),0) as TotalPostViews,
        coalesce(avg(rpa.Score),0) as AvgPostScore,
        max(rpa.LastUpvoteDate) as MostRecentUpvote
    from Users u
    left join RecentPostActivity rpa on rpa.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    having coalesce(sum(rpa.Score),0) > 1000
), TopPostsWithLinks as (
    select 
        p.Id, 
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        pt.Name as PostTypeName,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        pl.RelatedPostId,
        rp.Score as RelatedPostScore,
        rank() over (partition by p.Id order by rp.Score desc nulls last) as RelatedPostScoreRank
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join Posts rp on rp.Id = pl.RelatedPostId
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where p.Score > 50
), CombinedUserTagBadgeInfo as (
    select
        hau.UserId,
        hau.DisplayName,
        hau.Reputation,
        hau.TotalPostScore,
        hau.TotalPostViews,
        rub.GoldBadgeCount,
        rub.SilverBadgeCount,
        rub.BronzeBadgeCount,
        rub.LatestBadgeDate,
        string_agg(tt.Tag || ' (Posts: ' || tt.TagPostCount || ', Avg Score: ' || round(tt.AvgTagPostScore,2)::text || ')', ', ' order by tt.Tag) as TopTags
    from HighActivityUsers hau
    left join RecursiveUserBadges rub on rub.UserId = hau.UserId and rub.LatestBadgeRank = 1
    left join TopUserTags tt on tt.UserId = hau.UserId
    group by hau.UserId, hau.DisplayName, hau.Reputation, hau.TotalPostScore, hau.TotalPostViews, rub.GoldBadgeCount, rub.SilverBadgeCount, rub.BronzeBadgeCount, rub.LatestBadgeDate
)
select 
    cti.UserId,
    cti.DisplayName,
    cti.Reputation,
    cti.GoldBadgeCount,
    cti.SilverBadgeCount,
    cti.BronzeBadgeCount,
    to_char(cti.LatestBadgeDate, 'YYYY-MM-DD') as LatestBadgeAwarded,
    cti.TotalPostScore,
    cti.TotalPostViews,
    cti.TopTags,
    pwt.Title as PopularPostTitle,
    pwt.PostTypeName,
    pwt.Score as PopularPostScore,
    pwt.ViewCount as PopularPostViews,
    pwt.LinkTypeName,
    pwt.RelatedPostId,
    pwt.RelatedPostScore
from CombinedUserTagBadgeInfo cti
left join TopPostsWithLinks pwt on pwt.OwnerUserId = cti.UserId and pwt.RelatedPostScoreRank = 1
where cti.GoldBadgeCount + cti.SilverBadgeCount + cti.BronzeBadgeCount > 0
order by cti.Reputation desc, cti.TotalPostScore desc
limit 50;