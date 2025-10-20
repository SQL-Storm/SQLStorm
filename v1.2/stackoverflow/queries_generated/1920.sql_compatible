with RecursiveQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        u.Reputation,
        u.DisplayName,
        p.Score,
        p.ViewCount,
        dense_rank() over (partition by pp.Title order by p.CreationDate) as AnswerOrderByDate,
        coalesce(pp.Tags, '') as ParentTags
    from Posts p
    join Posts pp on p.ParentId = pp.Id and p.PostTypeId = 2
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 2
       or (p.PostTypeId = 1 and p.AcceptedAnswerId is not null)
)
select *
from RecursiveQuestions;