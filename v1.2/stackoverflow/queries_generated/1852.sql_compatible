with RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        u.DisplayName as OwnerName,
        a.CreationDate,
        row_number() over (
            partition by a.ParentId
            order by a.Score desc, a.CreationDate asc
        ) as AnswerRank,
        (
            select count(*)
            from Votes v_sub
            where v_sub.PostId = a.Id
              and v_sub.VoteTypeId = 2
        ) as UpVotesDetailed,
        (
            select count(*)
            from Votes v_sub2
            where v_sub2.PostId = a.Id
              and v_sub2.VoteTypeId = 3
        ) as DownVotesDetailed
    from Posts a 
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
QuestionsWithHighestUpsContributors as (
    select distinct
        q.Id,
        q.Title,
        u2.DisplayName as QuestionOwner,
        0 as DummyValue
    from Posts q
    left join Users u2 on q.OwnerUserId = u2.Id
    where q.PostTypeId = 1
)
select
    r.Id,
    r.ParentId,
    r.OwnerName,
    r.CreationDate,
    r.AnswerRank,
    r.UpVotesDetailed,
    r.DownVotesDetailed,
    q.Id as QuestionId,
    q.Title,
    q.QuestionOwner,
    q.DummyValue
from RankedAnswers r
left join QuestionsWithHighestUpsContributors q
    on r.ParentId = q.Id
where r.AnswerRank = 1;