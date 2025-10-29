-- {"query": "2525.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1091} 
with RecursiveUserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),

TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        u.DisplayName as AnswerOwner,
        row_number() over (partition by q.Id order by a.Score desc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1
),

CloseReasonsSummary as (
    select
        pht.PostId,
        string_agg(distinct cr.Name, ', ') as CloseReasons
    from PostHistory pht
    left join CloseReasonTypes cr on cast(pht.Comment as int) = cr.Id and pht.PostHistoryTypeId = 10
    group by pht.PostId
),

UserBadgesRanked as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as BadgeRank
    from Badges b
),

UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        count(p.Id) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        count(c.Id) over (partition by u.Id order by c.CreationDate range between interval '30 days' preceding and current row) as CommentsLast30Days,
        max(p.Score) over (partition by u.Id) as MaxPostScore,
        min(p.Score) over (partition by u.Id) as MinPostScore,
        avg(p.Score) over (partition by u.Id) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
),

HighActivityUsers as (
    select distinct UserId from UserActivityWindow
    where PostsLast30Days > 5 or CommentsLast30Days > 10
)

select distinct
    qs.QuestionId,
    qs.Title as QuestionTitle,
    qs.QuestionScore,
    qs.ViewCount,
    qs.Tags,
    qs.AnswerId,
    qs.AnswerScore,
    qs.AnswerDate,
    qs.AnswerOwner,
    crs.CloseReasons,
    rus.QuestionCount,
    rus.AnswerCount,
    rus.TotalPostScore,
    ub.BadgeName,
    ub.Class as BadgeClass,
    ua.MaxPostScore,
    ua.MinPostScore,
    ua.AvgPostScore
from TopQuestionsWithAnswers qs
left join CloseReasonsSummary crs on crs.PostId = qs.QuestionId
left join RecursiveUserPostStats rus on rus.UserId = (select OwnerUserId from Posts where Id = qs.QuestionId)
left join UserBadgesRanked ub on ub.UserId = rus.UserId and ub.BadgeRank <= 3
left join UserActivityWindow ua on ua.UserId = rus.UserId
where qs.AnswerRank = 1
and qs.QuestionScore > 5
and (crs.CloseReasons is null or crs.CloseReasons = '')
and rus.TotalPostScore > 10
and rus.UserId in (select UserId from HighActivityUsers)
union
select
    null as QuestionId,
    '[Aggregated Stats]' as QuestionTitle,
    null as QuestionScore,
    null as ViewCount,
    null as Tags,
    null as AnswerId,
    null as AnswerScore,
    null as AnswerDate,
    null as AnswerOwner,
    null as CloseReasons,
    count(distinct rus.UserId) as TotalUsers,
    sum(rus.QuestionCount) as TotalQuestions,
    sum(rus.AnswerCount) as TotalAnswers,
    null as BadgeName,
    null as BadgeClass,
    max(ua.MaxPostScore) as MaxPostScore,
    min(ua.MinPostScore) as MinPostScore,
    avg(ua.AvgPostScore) as AvgPostScore
from RecursiveUserPostStats rus
join UserActivityWindow ua on ua.UserId = rus.UserId
where rus.TotalPostScore > 50
order by QuestionScore desc nulls last, AnswerScore desc nulls last, BadgeClass asc nulls last, BadgeName nulls last;