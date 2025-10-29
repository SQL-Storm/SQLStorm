-- {"query": "2880.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1265} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        cast(t.TagName as varchar(35)) as FullPath,
        1 as Level
    from Tags t
    where t.IsRequired = 1
  union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        concat(r.FullPath, '>', t.TagName) as FullPath,
        r.Level + 1
    from Tags t
    inner join RecursiveTagHierarchy r on r.TagName = substring(t.TagName from 1 for length(r.TagName)) and r.Level < 3
),
QuestionStats as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        u.Reputation as OwnerReputation,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as OwnerRecentPostRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
),
AnswerAggregates as (
    select
        a.ParentId as QuestionId,
        count(*) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.CreationDate <= q.CreationDate + interval '7 days' then 1 else 0 end) as AnswersWithinWeek
    from Posts a
    join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    where a.PostTypeId = 2
    group by a.ParentId
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        count(*) over (partition by b.UserId, b.Class) as BadgesPerClass,
        row_number() over (partition by b.UserId order by b.Date desc) as RecentBadgeRank
    from Badges b
),
CloseReasonCounts as (
    select
        cht.Id as CloseReasonId,
        cht.Name as CloseReasonName,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes cht on ph.PostHistoryTypeId = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Id, cht.Name
),
PostLinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
UserPostEngagement as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(v.VoteTypeId = 2::int) as TotalUpVotes,
        sum(v.VoteTypeId = 3::int) as TotalDownVotes,
        sum(case when coalesce(b.Class, 0) = 1 then 1 else 0 end) as GoldBadges,
        sum(case when coalesce(b.Class, 0) = 2 then 1 else 0 end) as SilverBadges,
        sum(case when coalesce(b.Class, 0) = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId,
    q.OwnerReputation,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.AcceptedAnswerId,
    a.TotalAnswers,
    a.MaxAnswerScore,
    a.AvgAnswerScore,
    a.AnswersWithinWeek,
    b.BadgeName,
    b.Class as BadgeClass,
    b.BadgesPerClass,
    cr.CloseReasonName,
    pl.LinkTypeName,
    upeng.QuestionCount as UserQuestionCount,
    upeng.AnswerCount as UserAnswerCount,
    upeng.TotalUpVotes,
    upeng.TotalDownVotes,
    upeng.GoldBadges,
    upeng.SilverBadges,
    upeng.BronzeBadges,
    rh.FullPath as TagHierarchyPath
from QuestionStats q
left join AnswerAggregates a on a.QuestionId = q.Id
left join UserBadgeRanks b on b.UserId = q.OwnerUserId and b.RecentBadgeRank = 1
left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10
left join CloseReasonCounts cr on cr.CloseReasonId = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
left join PostLinkInfo pl on pl.PostId = q.Id
left join UserPostEngagement upeng on upeng.UserId = q.OwnerUserId
left join RecursiveTagHierarchy rh on rh.TagName = substring(q.Tags from 2 for charindex('>', q.Tags||'>') - 2)
where
    q.Score > 5
    and q.ViewCount > 1000
    and (a.AvgAnswerScore is null or a.AvgAnswerScore > 0)
    and (q.AcceptedAnswerId is not null or q.FavoriteCount > 0)
order by q.ViewCount desc, q.Score desc
limit 100;