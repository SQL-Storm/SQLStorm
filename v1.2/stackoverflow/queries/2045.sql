with
AuthorAnswerRanks as (
  select
    p.OwnerUserId,
    p.Id as AnswerId,
    p.ParentId as QuestionId,
    p.Score,
    dense_rank() over (
      partition by p.OwnerUserId order by p.Score desc
    ) as MakeSlopeTie_RankPerAuthor
  from posts p
  where p.PostTypeId = 2 /* answers */
    and p.OwnerUserId is not null
),
BaseUsersInfo as (
  select
    u.Id as UserId,
    u.DisplayName,
    coalesce(u.Reputation,0) as Reputation
  from users u
)
select *
from AuthorAnswerRanks a
join BaseUsersInfo u on u.UserId = a.OwnerUserId;