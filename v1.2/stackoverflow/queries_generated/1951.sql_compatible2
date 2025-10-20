with RecursiveTopTags as (
    select
        t.TagName,
        t.Count,
        ROW_NUMBER() over (order by t.Count desc) as rank
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
    order by t.Count desc
    limit 10
),
QuestionDataExp as (
    select
        p.Id as question_id,
        p.Title as question_title,
        p.OwnerUserId as question_owner_user_id,
        NULL as placeholder_rebuttal
    from Posts p
    where p.PostTypeId = 1
)
select
    r.TagName,
    r.Count,
    r.rank,
    q.question_id,
    q.question_title,
    q.question_owner_user_id,
    q.placeholder_rebuttal
from RecursiveTopTags r
left join QuestionDataExp q on q.question_id = r.rank
group by
    r.TagName,
    r.Count,
    r.rank,
    q.question_id,
    q.question_title,
    q.question_owner_user_id,
    q.placeholder_rebuttal
order by r.Count desc;