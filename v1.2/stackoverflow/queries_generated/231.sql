-- {"query": "231.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1277} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.TagBased = 0 or b.TagBased is null
),
TopBadges as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionAnswerStats as (
    select
        p.OwnerUserId,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionCount,
        count(case when p.PostTypeId = 2 then 1 end) as AnswerCount,
        avg(case when p.PostTypeId = 1 then p.Score end) as AvgQuestionScore,
        avg(case when p.PostTypeId = 2 then p.Score end) as AvgAnswerScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        count(distinct ph.Id) over (partition by u.Id order by ph.CreationDate range between interval '30 days' preceding and current row) as RecentEdits30d,
        count(distinct c.Id) over (partition by u.Id order by c.CreationDate range between interval '30 days' preceding and current row) as RecentComments30d
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        p.Title,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserReputationRank as (
    select
        Id,
        DisplayName,
        Reputation,
        rank() over (order by Reputation desc) as RepRank
    from Users
),
UserTagStringAgg as (
    select
        p.OwnerUserId,
        string_agg(distinct t.TagName, ', ' order by t.TagName) as UserTags
    from Posts p
    cross join lateral (
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName
    ) t
    where p.PostTypeId = 1 and p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
)
select
    u.Id as UserId,
    u.DisplayName,
    ur.RepRank,
    u.Reputation,
    coalesce(qas.QuestionCount,0) as QuestionCount,
    coalesce(qas.AnswerCount,0) as AnswerCount,
    coalesce(qas.AvgQuestionScore,0) as AvgQuestionScore,
    coalesce(qas.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(qas.TotalQuestionViews,0) as TotalQuestionViews,
    u.Location,
    u.CreationDate,
    u.LastAccessDate,
    uaw.RecentEdits30d,
    uaw.RecentComments30d,
    ut.UserTags,
    tb.BadgeName as TopBadge1,
    tb2.BadgeName as TopBadge2,
    tb3.BadgeName as TopBadge3,
    dq.PostTitle as DuplicatePostTitle,
    dq.RelatedPostTitle as DuplicateRelatedPostTitle,
    dq.CreationDate as DuplicateLinkDate,
    cqwr.Title as ClosedQuestionTitle,
    cqwr.CloseReason,
    cqwr.CloseDate
from Users u
left join QuestionAnswerStats qas on qas.OwnerUserId = u.Id
left join UserActivityWindow uaw on uaw.Id = u.Id
left join UserReputationRank ur on ur.Id = u.Id
left join UserTagStringAgg ut on ut.OwnerUserId = u.Id
left join TopBadges tb on tb.UserId = u.Id and tb.BadgeRank = 1
left join TopBadges tb2 on tb2.UserId = u.Id and tb2.BadgeRank = 2
left join TopBadges tb3 on tb3.UserId = u.Id and tb3.BadgeRank = 3
left join LATERAL (
    select dl.PostTitle, dl.RelatedPostTitle, dl.CreationDate
    from DuplicateLinks dl
    join Posts p on p.Id = dl.PostId
    where p.OwnerUserId = u.Id
    order by dl.CreationDate desc
    limit 1
) dq on true
left join LATERAL (
    select cq.Title, cq.CloseReason, cq.CloseDate
    from ClosedQuestionsWithReasons cq
    join Posts p on p.Id = cq.PostId
    where p.OwnerUserId = u.Id
    order by cq.CloseDate desc
    limit 1
) cqwr on true
where u.Reputation > 1000
order by u.Reputation desc
limit 100;