with RankedUserPosts as (
    select
        u.Id as UserId,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        row_number() over(partition by u.Id order by p.CreationDate desc) as Rn
    from 
        Users u
        left join Posts p on u.Id = p.OwnerUserId
    where u.Reputation > 1000
),
UserPostStats as (
    select
        rup.UserId,
        rup.PostTypeId,
        count(*) filter (where rup.PostTypeId = 1) as QuestionCount,
        count(*) filter (where rup.PostTypeId = 2) as AnswerCount,
        max(rup.Score) filter (where rup.PostTypeId in (1, 2)) as MaxPostScore,
        avg(nullif(rup.Score, 0) * 1.0) filter (where rup.PostTypeId in (1, 2)) as AvgPostScore
    from RankedUserPosts rup
    where rup.Rn <= 50
    group by rup.UserId, rup.PostTypeId
)
select
    u.UserId,
    u.PostTypeId,
    u.QuestionCount,
    u.AnswerCount,
    u.MaxPostScore,
    u.AvgPostScore
from UserPostStats u
order by u.UserId, u.PostTypeId;