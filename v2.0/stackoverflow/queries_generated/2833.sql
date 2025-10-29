-- {"query": "2833.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1536} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    where p.PostTypeId = 1 -- Questions only
    union all
    select
        rtc.TagId,
        rtc.TagName,
        p.Id,
        p.Score,
        p.ViewCount,
        p.CreationDate
    from RecursiveTagCounts rtc
    join Posts p on p.ParentId = rtc.PostId and p.PostTypeId = 2 -- Answers to questions in RecursiveTagCounts
),
TopUsersBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end),0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end),0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end),0) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as UserRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
    having count(b.Id) > 0
),
PostScoreStats as (
    select
        PostId,
        Score,
        ViewCount,
        OwnerUserId,
        Title,
        Tags,
        CreationDate,
        row_number() over (partition by OwnerUserId order by Score desc nulls last, ViewCount desc nulls last) as UserPostRank,
        count(*) over (partition by OwnerUserId) as TotalPosts
    from Posts
    where PostTypeId = 1
),
PostClosedCounts as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 else null end) as ClosedTimes,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as LastClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as LastReopenDate
    from PostHistory ph
    group by ph.PostId
),
UserPostSummary as (
    select
        ps.OwnerUserId,
        count(distinct ps.PostId) as QuestionCount,
        sum(coalesce(ps.Score,0)) as TotalScore,
        avg(coalesce(ps.Score,0)) as AvgScore,
        sum(coalesce(ps.ViewCount,0)) as TotalViews,
        sum(case when pcc.ClosedTimes > 0 then 1 else 0 end) as ClosedQuestionsCount
    from PostScoreStats ps
    left join PostClosedCounts pcc on pcc.PostId = ps.PostId
    group by ps.OwnerUserId
),
UsersWithBadgesAndPosts as (
    select
        t.UserId,
        t.DisplayName,
        t.GoldBadges,
        t.SilverBadges,
        t.BronzeBadges,
        up.QuestionCount,
        up.TotalScore,
        up.AvgScore,
        up.TotalViews,
        up.ClosedQuestionsCount,
        (t.GoldBadges*3 + t.SilverBadges*2 + t.BronzeBadges) as BadgeScore,
        (up.TotalScore * 0.5 + up.TotalViews * 0.02) as PostImpactScore
    from TopUsersBadgeCounts t
    left join UserPostSummary up on up.OwnerUserId = t.UserId
    where up.QuestionCount > 0
),
RecentCommentsWindowed as (
    select
        c.PostId,
        c.UserId,
        u.DisplayName,
        c.CreationDate,
        c.Text,
        rank() over (partition by c.PostId order by c.CreationDate desc) as CommentRank
    from Comments c
    left join Users u on u.Id = c.UserId
    where c.CreationDate > (current_date - interval '30 days')
),
PostLinksSummary as (
    select
        pl.PostId,
        sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as DuplicateLinks,
        sum(case when lt.Name = 'Linked' then 1 else 0 end) as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select distinct
    u.DisplayName as User,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.BadgeScore,
    u.QuestionCount,
    u.TotalScore,
    u.AvgScore,
    u.TotalViews,
    u.ClosedQuestionsCount,
    u.PostImpactScore,
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CreationDate as PostCreationDate,
    pcc.ClosedTimes,
    pcc.LastClosedDate,
    pcc.LastReopenDate,
    pls.DuplicateLinks,
    pls.LinkedPosts,
    string_agg(distinct rtc.TagName, ', ') filter (where rtc.TagName is not null) as RelatedTags,
    rc.CommentCountLast30Days,
    rc.LastCommentText
from UsersWithBadgesAndPosts u
join Posts p on p.OwnerUserId = u.UserId and p.PostTypeId = 1
left join PostClosedCounts pcc on pcc.PostId = p.Id
left join PostLinksSummary pls on pls.PostId = p.Id
left join RecursiveTagCounts rtc on rtc.PostId = p.Id
left join (
    select
        rc.PostId,
        count(*) as CommentCountLast30Days,
        max(rc.CreationDate) as LastCommentDate,
        max(rc.Text) as LastCommentText
    from RecentCommentsWindowed rc
    where rc.CommentRank = 1
    group by rc.PostId
) rc on rc.PostId = p.Id
where u.BadgeScore > 5
  and (p.Score > 5 or p.ViewCount > 1000)
  and (pcc.ClosedTimes is null or pcc.ClosedTimes = 0)
group by
    u.DisplayName,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.BadgeScore,
    u.QuestionCount,
    u.TotalScore,
    u.AvgScore,
    u.TotalViews,
    u.ClosedQuestionsCount,
    u.PostImpactScore,
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CreationDate,
    pcc.ClosedTimes,
    pcc.LastClosedDate,
    pcc.LastReopenDate,
    pls.DuplicateLinks,
    pls.LinkedPosts,
    rc.CommentCountLast30Days,
    rc.LastCommentText
order by u.BadgeScore desc, u.PostImpactScore desc, p.Score desc
limit 100;