-- {"query": "2128.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1048} 
with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Date, b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000 and b.Class is not null
),
TopBadges as (
    select UserId, BadgeName, Date, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionAnswerStats as (
    select p.Id as QuestionId, p.OwnerUserId, p.Title,
        p.CreationDate,
        coalesce(p.ViewCount, 0) as ViewCount,
        p.Score as QuestionScore,
        count(a.Id) filter (where a.Id is not null) as AnswerCount,
        max(a.Score) filter (where a.Id is not null) as MaxAnswerScore,
        avg(a.Score) filter (where a.Id is not null) as AvgAnswerScore
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1 and p.CreationDate > '2020-01-01'
    group by p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.ViewCount, p.Score
),
UserActivityWindow as (
    select u.Id as UserId, u.DisplayName, u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id) as AnswersGiven,
        lead(u.Reputation) over (order by u.Reputation desc) as NextHigherReputation,
        lag(u.Reputation) over (order by u.Reputation desc) as NextLowerReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > now() - interval '1 year'
),
DuplicateLinkedQuestions as (
    select pl.PostId as DuplicatePostId, pl.RelatedPostId as OriginalPostId,
        pq.Title as OriginalTitle, pq.CreationDate as OriginalCreationDate,
        pq.Score as OriginalScore, pq.ViewCount as OriginalViewCount
    from PostLinks pl
    inner join Posts pq on pq.Id = pl.RelatedPostId and pq.PostTypeId = 1
    where pl.LinkTypeId = 3 -- Duplicates
),
HighActivityUsers as (
    select u.Id, u.DisplayName,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.CreationDate > now() - interval '30 days') as PostsLast30Days,
        (select count(*) from Comments c where c.UserId = u.Id and c.CreationDate > now() - interval '30 days') as CommentsLast30Days
    from Users u
    where u.Reputation > 5000
)
select 
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.QuestionScore,
    q.AnswerCount,
    q.MaxAnswerScore,
    round(q.AvgAnswerScore,2) as AvgAnswerScore,
    u.DisplayName as OwnerDisplayName,
    u.Reputation as OwnerReputation,
    array_to_string(array_agg(distinct tb.BadgeName order by tb.Class), ', ') as TopBadges,
    dup.OriginalPostId,
    dup.OriginalTitle,
    dup.OriginalCreationDate,
    dup.OriginalScore,
    dup.OriginalViewCount,
    ha.PostsLast30Days,
    ha.CommentsLast30Days
from QuestionAnswerStats q
inner join Users u on q.OwnerUserId = u.Id
left join TopBadges tb on tb.UserId = u.Id
left join DuplicateLinkedQuestions dup on dup.DuplicatePostId = q.QuestionId
left join HighActivityUsers ha on ha.Id = u.Id
where q.AnswerCount > 5
and (q.QuestionScore > 10 or (q.MaxAnswerScore is not null and q.MaxAnswerScore > 20))
and (u.Reputation > 10000 or ha.PostsLast30Days > 10)
group by q.QuestionId, q.Title, q.CreationDate, q.ViewCount, q.QuestionScore, q.AnswerCount, q.MaxAnswerScore, q.AvgAnswerScore,
    u.DisplayName, u.Reputation,
    dup.OriginalPostId, dup.OriginalTitle, dup.OriginalCreationDate, dup.OriginalScore, dup.OriginalViewCount,
    ha.PostsLast30Days, ha.CommentsLast30Days
having count(distinct tb.BadgeName) >= 1
order by q.ViewCount desc, q.QuestionScore desc
limit 100;