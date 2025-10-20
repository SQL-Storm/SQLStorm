with QuestionRanking as (
  select
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    count(com.Id) as CommentNum,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    row_number() over (order by p.Score desc, p.ViewCount desc, p.CreationDate) as Rank
  from Posts p
    left join Comments com on com.PostId = p.Id and com.UserId is not null
    left join Votes v on v.PostId = p.Id
  where p.PostTypeId = 1
  group by
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags
)
select *
from QuestionRanking;