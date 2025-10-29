-- {"query": "2981.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1659} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId, 
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over(partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date >= '2020-01-01' or b.Id is null
),
TopBadgeUsers as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where rn <= 3
),
RecentEditedPosts as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        ph.CreationDate as LastEditDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorName,
        row_number() over(partition by p.Id order by ph.CreationDate desc) as rn
    from Posts p
    inner join PostHistory ph on p.Id = ph.PostId
    where ph.PostHistoryTypeId in (4,5,6) -- edits to Title, Body or Tags
),
DistinctLinkCounts as (
    select 
        p.Id as PostId,
        count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId else null end) as LinkCount,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId else null end) as DuplicateCount
    from Posts p
    left join PostLinks pl on p.Id = pl.PostId
    group by p.Id
),
UserActivity as (
    select 
        u.Id as UserId,
        coalesce(u.Reputation,0) as Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesCast,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesCast
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    left join Votes v on u.Id = v.UserId
    group by u.Id, u.Reputation
),
TopPostsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        row_number() over(partition by q.Id order by a.Score desc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1 and q.AnswerCount > 0
),
FilteredTopAnswers as (
    select *
    from TopPostsWithAnswers
    where AnswerRank <= 2
),
PostClosureInfo as (
    select 
        p.Id as PostId,
        p.Title,
        p.ClosedDate,
        crt.Name as CloseReason
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
    where p.ClosedDate is not null
),
TagPopularity as (
    select 
        t.Id as TagId,
        t.TagName,
        t.Count as UsageCount,
        (select count(*) from Posts p where p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1) as QuestionCount,
        (select count(*) from Posts p where p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 2) as AnswerCount
    from Tags t
),
PopularTagsPerformance as (
    select 
        tp.TagName,
        tp.UsageCount,
        tp.QuestionCount,
        tp.AnswerCount,
        avg(p.Score) as AvgPostScore,
        sum(p.ViewCount) as TotalViews,
        max(p.CreationDate) as MostRecentPost
    from TagPopularity tp
    left join Posts p on p.Tags like concat('%<', tp.TagName, '>%') and p.PostTypeId in (1,2)
    group by tp.TagName, tp.UsageCount, tp.QuestionCount, tp.AnswerCount
    having tp.UsageCount > 1000
),
UserBadgeSummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
AnswerAcceptanceStats as (
    select 
        a.OwnerUserId,
        count(a.Id) as TotalAnswers,
        count(case when q.AcceptedAnswerId = a.Id then 1 else null end) as AcceptedCount,
        avg(a.Score) as AvgAnswerScore,
        sum(case when q.AcceptedAnswerId = a.Id then 1 else 0 end) * 1.0 / nullif(count(a.Id),0) as AcceptanceRate
    from Posts a
    inner join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
    group by a.OwnerUserId
)

select 
    u.Id as UserId,
    u.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.UpVotesCast,
    ua.DownVotesCast,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    aavs.TotalAnswers,
    aavs.AcceptedCount,
    aavs.AcceptanceRate,
    ptd.PostId,
    ptd.Title as PostTitle,
    ptd.LastEditDate,
    ptd.EditorUserId,
    ptd.EditorName,
    dlc.LinkCount,
    dlc.DuplicateCount,
    pci.ClosedDate,
    pci.CloseReason,
    ptp.TagName,
    ptp.UsageCount,
    ptp.QuestionCount as TagQuestions,
    ptp.AnswerCount as TagAnswers,
    ptp.AvgPostScore,
    ptp.TotalViews,
    ptp.MostRecentPost
from Users u
left join UserActivity ua on u.Id = ua.UserId
left join UserBadgeSummary ubs on u.Id = ubs.UserId
left join AnswerAcceptanceStats aavs on u.Id = aavs.OwnerUserId
left join RecentEditedPosts ptd on ptd.OwnerUserId = u.Id and ptd.rn = 1
left join DistinctLinkCounts dlc on dlc.PostId = ptd.PostId
left join PostClosureInfo pci on pci.PostId = ptd.PostId
left join PopularTagsPerformance ptp on ptd.Tags like concat('%<', ptp.TagName, '>%')
where ua.QuestionCount > 5 and aavs.AcceptanceRate > 0.5
order by ua.Reputation desc, u.Id
limit 100;