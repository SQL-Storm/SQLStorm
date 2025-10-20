with RecursiveRecentAnswers as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.CreationDate,
        p.Score,
        dense_rank() over (partition by p.ParentId order by p.Score desc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2 -- Answer
      and p.CreationDate > cast('2024-10-01' as date) - interval '180 days'
),
TopAnswers as (
    select
        AnswerId, QuestionId, CreationDate, Score
    from RecursiveRecentAnswers
    where AnswerRank <= 3
),
QuestionBadges as (
    select distinct 
        p.Id as PostId,
        b.Name as BadgeName,
        pt.Name as PostTypeName,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) as BadgeRowNum
    from Posts p
    inner join Users u on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id 
    join PostTypes pt on p.PostTypeId = pt.Id
    where p.PostTypeId in (1,2)
),
QuestionCommentsCTE as (
    select
        c.PostId,
        count(case when vn.VoteTypeId = 2 then 1 end) as UpVotes,
        count(case when vn.VoteTypeId = 3 then 1 end) as DownVotes
    from Comments c
    left join Votes vn on vn.PostId = c.PostId and vn.CreationDate > c.CreationDate and vn.VoteTypeId in (2,3)
    group by c.PostId
),
QuestionWithRanking as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        coalesce(qc.UpVotes, 0) as UpVotes,
        coalesce(qc.DownVotes, 0) as DownVotes,
        qb.BadgeName,
        qb.PostTypeName,
        qb.Class,
        ta.AnswerId,
        ta.CreationDate as AnswerCreationDate,
        ta.Score as AnswerScore,
        dense_rank() over (partition by q.Id order by ta.Score desc) as AnswerRank
    from Posts q
    left join QuestionCommentsCTE qc on qc.PostId = q.Id
    left join QuestionBadges qb on qb.PostId = q.Id
    left join TopAnswers ta on ta.QuestionId = q.Id
    where q.PostTypeId = 1
)
select
    qwr.QuestionId,
    qwr.Title,
    qwr.Score as QuestionScore,
    qwr.ViewCount,
    qwr.UpVotes,
    qwr.DownVotes,
    qwr.BadgeName,
    qwr.PostTypeName,
    qwr.Class,
    qwr.AnswerId,
    qwr.AnswerCreationDate,
    qwr.AnswerScore,
    qwr.AnswerRank
from QuestionWithRanking qwr
order by qwr.Score desc, qwr.ViewCount desc;