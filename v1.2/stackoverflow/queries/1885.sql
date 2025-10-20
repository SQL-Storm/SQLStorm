with RecursiveTopTags as (
    select
        t.TagName,
        t.Count,
        coalesce(
            (
                select ph2.Comment
                from PostHistory ph2
                where ph2.PostId = t.ExcerptPostId
                  and ph2.Comment is not null
                limit 1
            ),
            ''
        ) as TagExcerpt
    from Tags t
)
select *
from RecursiveTopTags;