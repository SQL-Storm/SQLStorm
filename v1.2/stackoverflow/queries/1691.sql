with RecursiveTagCount AS (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(pz.AnswerCount, 0) as AnswerCountSum,
        coalesce(pq.ScoreAverage, 0) as AvgQuestionScore,
        coalesce(pqMax.ScoreMax, 0) as MaxQuestionScore
    from
        Tags t
    left join lateral (
        select count(a.Id) as AnswerCount
        from Posts q
        join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
        where q.Id = t.ExcerptPostId or q.Id = t.WikiPostId
    ) pz on true
    left join lateral (
        select avg(pi.Score) as ScoreAverage
        from Posts pi
        where pi.PostTypeId = 1 and (pi.Id = t.ExcerptPostId or pi.Id = t.WikiPostId)
    ) pq on true
    left join lateral (
        select max(pi.Score) as ScoreMax
        from Posts pi
        where pi.PostTypeId = 1 and (pi.Id = t.ExcerptPostId or pi.Id = t.WikiPostId)
    ) pqMax on true
)
select
    Id,
    TagName,
    Count,
    AnswerCountSum,
    AvgQuestionScore,
    MaxQuestionScore
from RecursiveTagCount;