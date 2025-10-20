with RankedBadges as (
    select
        UserId,
        Name,
        Class,
        Date,
        row_number() over (
            partition by UserId
            order by Date asc
        ) as rn
    from Badges
    where Name is not null
), TopUserBadges as (
    select rbu.UserId, rbu.Name, rbu.Class, rbu.Date
    from RankedBadges rbu
    where rn <= 5
), QuestionsWithAcceptedAnswers as (
    select
        p.Id as QuestionId,
        p.Score as QuestionScore,
        COALESCE(
            (
                select pa.Score
                from Posts pa
                where pa.Id = p.AcceptedAnswerId
            ), -9999999
        ) as AcceptedAnswerScore,
        u.Id as OwnerId,
        u.DisplayName,
        u.Reputation
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
)
select
    q.QuestionId,
    q.QuestionScore,
    q.AcceptedAnswerScore,
    q.OwnerId,
    q.DisplayName,
    q.Reputation,
    t.Name as BadgeName,
    t.Class as BadgeClass,
    t.Date as BadgeDate
from QuestionsWithAcceptedAnswers q
left join TopUserBadges t
    on t.UserId = q.OwnerId
order by q.QuestionId, t.Date;