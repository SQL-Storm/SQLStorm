with recursive RecentPostsCTE as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COALESCE(u.Reputation, 0) as OwnerReputation,
        ROW_NUMBER() OVER (partition by p.PostTypeId order by p.CreationDate desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.CreationDate >= cast('2024-10-01' as date) - interval '60 days'
),
TopQuestions as (
    select 
        Id,
        OwnerUserId,
        CreationDate,
        Score,
        ViewCount,
        Tags,
        OwnerReputation
    from RecentPostsCTE
    where PostTypeId = 1 and rn <= 10
),
AnswerAggregates as (
    select 
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        sum(case when a.Score > 0 then a.Score else 0 end) as TotalPositiveScore,
        avg(a.Score) as AvgAnswerScore,
        max(u.Reputation) as TopOwnerReputation
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
    group by a.ParentId
)
select
    q.Id as QuestionId,
    q.OwnerUserId,
    q.CreationDate,
    q.Score as QuestionScore,
    q.ViewCount,
    q.Tags,
    q.OwnerReputation,
    coalesce(aa.AnswerCount, 0) as AnswerCount,
    coalesce(aa.TotalPositiveScore, 0) as TotalPositiveScore,
    aa.AvgAnswerScore,
    aa.TopOwnerReputation
from TopQuestions q
left join AnswerAggregates aa on aa.QuestionId = q.Id
order by q.CreationDate desc;