with recursive RecursiveQuestions as (
    select p.Id, p.Title, p.OwnerUserId, 0 as RecursionDepth
    from Posts p
    where p.PostTypeId = 1 and p.Id in (
        select AcceptedAnswerId from Posts where AcceptedAnswerId is not null
    )
    union all
    select p.Id, p.Title, p.OwnerUserId, rq.RecursionDepth + 1
    from Posts p
    join RecursiveQuestions rq on p.Id = rq.Id -- fixed join to reference existing column
    where p.PostTypeId = 2
), PostTagsSplit as (
    select
        p.Id as PostId,
        trim(both '<' from trim(both '>' from t.value)) as Tag
    from Posts p
    cross join lateral (
        -- Normalize tags like '<tag1><tag2>' into a string suitable for splitting, then split on '><'
        select regexp_split_to_table(
            replace(coalesce(p.Tags, ''), '><', '><'),
            '><'
        ) as value
    ) t
), QuestionAnswerStats as (
    select
        rq.Id as QuestionId,
        rq.Title,
        rq.OwnerUserId,
        rq.RecursionDepth,
        pa.Id as AnswerId,
        pa.OwnerUserId as AnswerOwnerUserId,
        pa.Score as AnswerScore,
        pa.CreationDate as AnswerCreationDate,
        pts.PostId,
        pts.Tag
    from RecursiveQuestions rq
    left join Posts pa on pa.ParentId = rq.Id and pa.PostTypeId = 2
    left join PostTagsSplit pts on pts.PostId = rq.Id
)
select
    QuestionId,
    Title,
    OwnerUserId,
    RecursionDepth,
    AnswerId,
    AnswerOwnerUserId,
    AnswerScore,
    AnswerCreationDate,
    Tag
from QuestionAnswerStats
group by
    QuestionId,
    Title,
    OwnerUserId,
    RecursionDepth,
    AnswerId,
    AnswerOwnerUserId,
    AnswerScore,
    AnswerCreationDate,
    Tag;