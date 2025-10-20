with ranked_user_posts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        case 
            when p.PostTypeId = 1 then (select count(*) from Posts answer where answer.ParentId = p.Id)
            else null
        end as AnswerCountRecall,
        row_number() over(partition by u.Id order by p.Score desc, p.ViewCount desc) as PostRank,
        count(*) over(partition by u.Id) as TotalPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Location is not null
)
select *
from ranked_user_posts;