-- {"query": "2295.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1176} 
with RankedUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Class, b.Date desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.TagBased = 0 and b.Class in (1,2,3)
), 
UserTopBadges as (
    select UserId, BadgeName, Class from RankedUserBadges where BadgeRank <= 3
),
PostAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        count(a.Id) as AnswerCount,
        coalesce(sum(a.Score),0) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId
),
UserReputationWindow as (
    select 
        Id, DisplayName, Reputation,
        rank() over (order by Reputation desc) as ReputationRank,
        dense_rank() over (partition by coalesce(Location,'Unknown') order by Reputation desc) as LocationReputationRank
    from Users
),
QuestionCommentStats as (
    select 
        p.Id as PostId,
        count(c.Id) as CommentCount,
        sum(case when c.Score >= 0 then 1 else 0 end) as NonNegativeComments,
        sum(case when c.Score < 0 then 1 else 0 end) as NegativeComments
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1,2)
    group by p.Id
),
LatestPostHistoryEdits as (
    select ph.PostId, max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.PostId
),
PostLinkDuplicates as (
    select p.Id as PostId, count(distinct pl.RelatedPostId) as DuplicateCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    where p.PostTypeId = 1
    group by p.Id
),
UserActivityRank as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) as TotalVotes,
        row_number() over (order by count(distinct p.Id) desc, u.Reputation desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
)
select 
    q.Title,
    u.DisplayName as QuestionOwner,
    qas.AnswerCount,
    qas.TotalAnswerScore,
    qas.MaxAnswerScore,
    qas.AvgAnswerScore,
    coalesce(pcs.CommentCount,0) as QuestionCommentCount,
    coalesce(pld.DuplicateCount,0) as DuplicateReferenceCount,
    urb.BadgeName as TopBadgeName,
    urb.Class as BadgeClass,
    urw.ReputationRank,
    urw.LocationReputationRank,
    uar.TotalPosts,
    uar.TotalComments,
    uar.TotalVotes,
    uar.ActivityRank,
    case 
        when qas.MaxAnswerScore > 0 then 'Popular'
        when qas.AnswerCount = 0 then 'Unanswered'
        else 'Normal'
    end as QuestionStatus,
    coalesce(lphe.LastEditDate, qas.LastEditDate) as LastEditTimestamp,
    -- String manipulation example
    substring(q.Title from 1 for 50) || coalesce('...' , '') as ShortTitleExcerpt,
    -- Correlated subquery example
    (select count(1) from Votes v2 where v2.PostId = q.QuestionId and v2.VoteTypeId = 2) as QuestionUpVotes,
    -- NULL logic example
    case when u.WebsiteUrl is null then 'No Website' else u.WebsiteUrl end as UserWebsite,
    -- Complex predicate example
    case when u.Reputation > 10000 and uar.ActivityRank <= 100 then 'Top User' else 'Regular User' end as UserStatus
from PostAnswerStats qas
join Users u on u.Id = qas.OwnerUserId
left join UserTopBadges urb on urb.UserId = u.Id and urb.BadgeRank = 1
left join UserReputationWindow urw on urw.Id = u.Id
left join QuestionCommentStats pcs on pcs.PostId = qas.QuestionId
left join PostLinkDuplicates pld on pld.PostId = qas.QuestionId
left join LatestPostHistoryEdits lphe on lphe.PostId = qas.QuestionId
left join UserActivityRank uar on uar.Id = u.Id
left join Posts q on qas.QuestionId = q.Id
where qas.AnswerCount >= 1
order by uar.ActivityRank, qas.AnswerCount desc
limit 100;