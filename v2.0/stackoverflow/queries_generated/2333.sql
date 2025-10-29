-- {"query": "2333.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1630} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        0 as ActivityScore,
        0 as AnsweredCount,
        0 as QuestionCount,
        0 as CommentCount
    from Users u

    union all

    select 
        p.OwnerUserId as UserId,
        u2.DisplayName,
        u2.Reputation,
        u2.CreationDate,
        u2.LastAccessDate,
        ru.ActivityScore + (case when p.PostTypeId = 1 then p.Score * 10 else 0 end) + (case when p.PostTypeId = 2 then p.Score * 15 else 0 end),
        ru.AnsweredCount + (case when p.PostTypeId = 2 then 1 else 0 end),
        ru.QuestionCount + (case when p.PostTypeId = 1 then 1 else 0 end),
        ru.CommentCount
    from RecursiveUserActivity ru
    join Posts p on p.OwnerUserId = ru.UserId and p.OwnerUserId > 0
    join Users u2 on u2.Id = p.OwnerUserId
    where ru.ActivityScore < 1000000 -- limit recursion depth to prevent infinite loop

    union all

    select 
        c.UserId,
        u3.DisplayName,
        u3.Reputation,
        u3.CreationDate,
        u3.LastAccessDate,
        ru2.ActivityScore + c.Score * 2,
        ru2.AnsweredCount,
        ru2.QuestionCount,
        ru2.CommentCount + 1
    from RecursiveUserActivity ru2
    join Comments c on c.UserId = ru2.UserId and c.UserId is not null
    join Users u3 on u3.Id = c.UserId
    where ru2.ActivityScore < 1000000
),
LatestPostLinks as (
    select distinct on (pl.PostId, pl.RelatedPostId) 
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        pl.CreationDate
    from PostLinks pl
    order by pl.PostId, pl.RelatedPostId, pl.CreationDate desc
),
UserBadgeRanks as (
    select 
        b.UserId, 
        b.Name as BadgeName, 
        b.Class as BadgeClass,
        row_number() over (partition by b.UserId order by b.Class asc, b.Date desc) as rn
    from Badges b
    where b.Class in (1,2,3)
),
UserTopBadges as (
    select ub.UserId, string_agg(ub.BadgeName, ', ' order by ub.BadgeClass, ub.rn) as BadgesList
    from UserBadgeRanks ub
    where ub.rn <= 3
    group by ub.UserId
),
QuestionAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreated,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as AnswersCount,
        max(a.Score) as HighestAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        array_to_string(array_agg(distinct au.DisplayName), ', ') as Answerers,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswerExists,
        -- Correlated subquery to get count of comments on question
        (select count(*) from Comments c where c.PostId = q.Id) as QuestionComments,
        -- Correlated subquery to get count of comments on answers
        (select count(*) from Comments c where c.PostId in (select a2.Id from Posts a2 where a2.ParentId = q.Id)) as AnswerComments
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users au on au.Id = a.OwnerUserId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.AcceptedAnswerId
),
TagArrayExtract as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as TagName
    from QuestionAnswers q
),
TagPopularity as (
    select 
        t.TagName,
        count(distinct qa.QuestionId) as QuestionsWithTag,
        avg(qa.QuestionScore) as AverageQuestionScore,
        avg(qa.AnswersCount) as AvgAnswersPerQuestion,
        sum(case when qa.AcceptedAnswerExists > 0 then 1 else 0 end) as AcceptedAnswersCount
    from TagArrayExtract t
    join QuestionAnswers qa on qa.QuestionId = t.QuestionId
    group by t.TagName
),
RankedUserActivity as (
    select
        UserId,
        DisplayName,
        Reputation,
        ActivityScore,
        AnsweredCount,
        QuestionCount,
        CommentCount,
        row_number() over (order by ActivityScore desc nulls last, Reputation desc nulls last) as ActivityRank
    from RecursiveUserActivity
    where UserId is not null
),
UserLastActivity as (
    select 
        u.Id as UserId,
        max(ph.CreationDate) as LastEditTimestamp,
        max(v.CreationDate) as LastVoteTimestamp,
        max(c.CreationDate) as LastCommentTimestamp
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id
)
select 
    q.QuestionId,
    q.Title,
    q.QuestionCreated,
    q.QuestionScore,
    q.ViewCount,
    q.AnswersCount,
    q.HighestAnswerScore,
    round(q.AvgAnswerScore,2) as AvgAnswerScore,
    q.Answerers,
    q.AcceptedAnswerExists > 0 as HasAcceptedAnswer,
    q.QuestionComments,
    q.AnswerComments,
    t.TagName,
    t.QuestionsWithTag,
    round(t.AverageQuestionScore,2) as AverageTagQuestionScore,
    round(t.AvgAnswersPerQuestion,2) as AvgAnswersPerTagQuestion,
    t.AcceptedAnswersCount,
    ru.ActivityScore as OwnerActivityScore,
    ru.AnsweredCount as OwnerAnswerCount,
    ru.QuestionCount as OwnerQuestionCount,
    ru.CommentCount as OwnerCommentCount,
    ru.Reputation as OwnerReputation,
    rnk.ActivityRank as OwnerActivityRank,
    ub.BadgesList as OwnerTopBadges,
    ul.LastEditTimestamp,
    ul.LastVoteTimestamp,
    ul.LastCommentTimestamp
from QuestionAnswers q
left join TagArrayExtract tge on tge.QuestionId = q.QuestionId
left join TagPopularity t on t.TagName = tge.TagName
left join Users u on u.Id = (select OwnerUserId from Posts p where p.Id = q.QuestionId)
left join RecursiveUserActivity ru on ru.UserId = u.Id
left join RankedUserActivity rnk on rnk.UserId = u.Id
left join UserTopBadges ub on ub.UserId = u.Id
left join UserLastActivity ul on ul.UserId = u.Id
where q.AnswersCount > 0 
  and t.QuestionsWithTag > 5
order by q.QuestionScore desc nulls last, q.AnswersCount desc nulls last, ru.ActivityScore desc nulls last
limit 100;