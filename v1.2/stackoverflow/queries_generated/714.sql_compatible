with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Class, b.Date,
           row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
TopUserBadges as (
    select UserId, DisplayName, BadgeName, Class, Date, rn
    from RecursiveUserBadges
    where rn <= 3
),
RecentQuestionStats as (
    select p.OwnerUserId, count(*) as QuestionCount,
           avg(p.Score) as AvgScore,
           sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as AcceptedCount,
           max(p.ViewCount) as MaxViewCount,
           string_agg(distinct substring(t.TagName from 1 for 10), ', ') as SampleTags
    from Posts p
    left join Tags t on p.Tags like '%' || t.TagName || '%'
    where p.PostTypeId = 1
      and p.CreationDate >= cast('2024-10-01' as date) - interval '30 days'
      and p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopAnswersWithComments as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.OwnerUserId as AnswererId,
           a.Score as AnswerScore, a.CreationDate as AnswerDate,
           c.Id as CommentId, c.Text as CommentText, c.CreationDate as CommentDate,
           row_number() over (partition by a.Id order by c.CreationDate desc nulls last) as CommentRank
    from Posts a
    left join Comments c on a.Id = c.PostId
    where a.PostTypeId = 2
      and a.Score > 10
),
LatestAnswerComments as (
    select AnswerId, QuestionId, AnswererId, AnswerScore, AnswerDate, CommentId, CommentText, CommentDate
    from TopAnswersWithComments
    where CommentRank = 1
),
QuestionsClosedRecently as (
    select p.Id, p.Title, p.OwnerUserId, p.CreationDate, ph.Comment as CloseReasonId, crt.Name as CloseReasonName
    from Posts p
    inner join PostHistory ph on p.Id = ph.PostId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where p.PostTypeId = 1
      and ph.CreationDate >= cast('2024-10-01' as date) - interval '60 days'
),
UserActivityRanks as (
    select u.Id, u.DisplayName,
           rank() over (order by coalesce(ru.QuestionCount,0) desc) as QuestionRank,
           rank() over (order by coalesce(a.AnswerCount,0) desc) as AnswerRank,
           rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) ru on u.Id = ru.OwnerUserId
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) a on u.Id = a.OwnerUserId
)
select 
    u.Id as UserId,
    u.DisplayName,
    ua.QuestionRank,
    ua.AnswerRank,
    ua.ReputationRank,
    coalesce(rqs.QuestionCount,0) as RecentQuestions,
    coalesce(rqs.AvgScore,0) as AvgQuestionScore,
    coalesce(rqs.AcceptedCount,0) as AcceptedQuestions,
    coalesce(rqs.MaxViewCount,0) as MaxQuestionViews,
    coalesce(rqs.SampleTags, 'None') as SampleTags,
    tab.BadgeName,
    tab.Class as BadgeClass,
    lac.AnswerId,
    lac.AnswerScore,
    lac.CommentText as LatestCommentOnTopAnswer,
    qc.Title as RecentlyClosedQuestionTitle,
    qc.CloseReasonName as LastCloseReason
from Users u
left join UserActivityRanks ua on u.Id = ua.Id
left join RecentQuestionStats rqs on u.Id = rqs.OwnerUserId
left join TopUserBadges tab on u.Id = tab.UserId and tab.rn = 1
left join LatestAnswerComments lac on u.Id = lac.AnswererId
left join QuestionsClosedRecently qc on u.Id = qc.OwnerUserId
where u.Reputation > 1000
  and (coalesce(rqs.QuestionCount,0) > 5 or coalesce(lac.AnswerScore,0) > 20)
group by
    u.Id, u.DisplayName,
    ua.QuestionRank, ua.AnswerRank, ua.ReputationRank,
    rqs.QuestionCount, rqs.AvgScore, rqs.AcceptedCount, rqs.MaxViewCount, rqs.SampleTags,
    tab.BadgeName, tab.Class, tab.UserId, tab.rn,
    lac.AnswerId, lac.AnswerScore, lac.CommentText, lac.AnswererId,
    qc.Title, qc.CloseReasonName, qc.OwnerUserId
order by ua.ReputationRank, RecentQuestions desc
limit 100;