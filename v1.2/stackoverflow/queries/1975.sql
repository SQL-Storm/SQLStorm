with RecursivePopularityUserRank as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        row_number() over(order by u.Reputation desc) as ReputeRank
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join Posts p2 on p2.OwnerUserId = u.Id
    group by
        u.Id,
        u.DisplayName,
        u.Reputation
)
select *
from RecursivePopularityUserRank;