with RankedPosts as (
    select 
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Title,
        eu.DisplayName as EditorUser,
        counts.AnswersCount,
        weights.AgeScore,
        ranks.RowNumQuestions,
        ranks.RowNumAnswers
    from Posts p
    left join Users eu on eu.Id = p.LastEditorUserId
    left join (
        select ParentId, count(*) as AnswersCount
        from Posts p2
        where p2.PostTypeId = 2
        group by ParentId
    ) counts on counts.ParentId = p.Id
    left join (
        select Id,
               0.0 as AgeScore
        from Posts
    ) weights on weights.Id = p.Id
    left join (
        select Id,
               row_number() over (order by CreationDate) as RowNumQuestions,
               cast(null as integer) as RowNumAnswers,
               CreationDate
        from Posts
        where PostTypeId = 1
        group by Id, CreationDate
    ) ranks on ranks.Id = p.Id
)
select Id, PostTypeId, CreationDate, Score, ViewCount, Title, EditorUser, AnswersCount, AgeScore, RowNumQuestions, RowNumAnswers
from RankedPosts;