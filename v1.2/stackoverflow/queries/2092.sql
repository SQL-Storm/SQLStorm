with UserExpertise AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1 and p.Score > 10) as HighScoringQuestions,
        count(distinct a.Id) filter (where a.PostTypeId = 2 and a.Score > 5) as HighScoringAnswers
    from users u
    left join posts p on p.OwnerUserId = u.Id
    left join posts a on a.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
UserActivity AS (
    select
        u.Id as UserId,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        max(p.CreationDate) as LastPostDate
    from users u
    left join posts p on p.OwnerUserId = u.Id
    group by u.Id
),
ScoreBuckets AS (
    select
        u.Id as UserId,
        case
            when u.Reputation >= 100000 then '100k+'
            when u.Reputation >= 10000 then '10k-99k'
            when u.Reputation >= 1000 then '1k-9k'
            when u.Reputation >= 100 then '100-999'
            else '<100'
        end as ReputationBucket
    from users u
    group by u.Id, u.Reputation
)
select
    ue.UserId,
    ue.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ue.HighScoringQuestions,
    ue.HighScoringAnswers,
    sb.ReputationBucket,
    ua.LastPostDate
from UserExpertise ue
join UserActivity ua on ua.UserId = ue.UserId
left join ScoreBuckets sb on sb.UserId = ue.UserId
order by ue.HighScoringAnswers desc, ue.HighScoringQuestions desc, ua.AnswerCount desc;