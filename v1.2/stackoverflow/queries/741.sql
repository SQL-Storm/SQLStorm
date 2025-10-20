-- {"query": "741.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1155} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Id) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        p.Title,
        count(c.Id) over (partition by p.Id) as CommentCountWindow,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1,2)
),
TopActiveUsers as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.TotalBadges,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        count(distinct p.Id) as PostsCount,
        sum(p.Score) as TotalScore,
        avg(p.CommentCount) as AvgComments,
        max(p.CreationDate) as LastPostDate
    from UserBadgeStats ua
    left join Posts p on p.OwnerUserId = ua.UserId
    where ua.TotalBadges > 5
    group by ua.UserId, ua.DisplayName, ua.TotalBadges, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges
    having count(distinct p.Id) > 10
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
CloseReasonsSummary as (
    select
        cht.Id,
        cht.Name,
        count(ph.Id) as CloseCount
    from CloseReasonTypes cht
    left join PostHistory ph on ph.PostHistoryTypeId = 10 and ph.Comment = cast(cht.Id as varchar)
    group by cht.Id, cht.Name
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(ph.CreationDate) as LastActivity,
        count(ph.Id) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenCount,
        count(ph.Id) filter (where ph.PostHistoryTypeId = 24) as SuggestedEdits,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    rt.TagName,
    rt.Count as TagCount,
    rt.TotalAnswers,
    rt.TotalViews,
    tu.DisplayName as TopUserDisplayName,
    tu.TotalBadges,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.PostsCount,
    tu.TotalScore,
    tu.AvgComments,
    dr.PostTitle as DuplicateFromPost,
    dr.RelatedPostTitle as DuplicateToPost,
    cr.Name as CloseReasonName,
    cr.CloseCount,
    ura.LastActivity as UserLastActivity,
    ura.CloseReopenCount,
    ura.SuggestedEdits,
    ura.UpVotesReceived
from RecursiveTagCounts rt
left join TopActiveUsers tu on tu.DisplayName ilike '%' || rt.TagName || '%'
left join DuplicateLinks dr on dr.PostId = (
    select p.Id from Posts p where p.Tags ilike '%' || rt.TagName || '%' order by p.Score desc limit 1
)
left join CloseReasonsSummary cr on cr.Id = (
    select cast(ph.Comment as int) from PostHistory ph
    where ph.PostHistoryTypeId = 10 and ph.PostId = dr.PostId limit 1
)
left join UserRecentActivity ura on ura.UserId = (
    select p.OwnerUserId from Posts p where p.Tags ilike '%' || rt.TagName || '%' order by p.CreationDate desc limit 1
)
where rt.TagRank <= 50
order by rt.TagRank, tu.TotalBadges desc
limit 100;