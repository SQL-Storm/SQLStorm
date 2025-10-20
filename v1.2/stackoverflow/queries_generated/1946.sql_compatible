with RankedAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        ROW_NUMBER() over (partition by p.ParentId order by p.Score desc, p.ViewCount desc) as AnswerRank,
        dense_rank() over (partition by p.ParentId order by p.OwnerUserId) as UserChronoRank,
        case
            when U.DisplayName is null then '[Unknown]'
            else U.DisplayName
        end as DisplayName
    from posts p
    left join users U
        on p.OwnerUserId = U.Id
    where p.PostTypeId = 2
)
select
    r.ParentId,
    r.Id,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.DisplayName,
    r.AnswerRank,
    r.UserChronoRank
from RankedAnswers r
order by r.ParentId, r.AnswerRank, r.UserChronoRank;