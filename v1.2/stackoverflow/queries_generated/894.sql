-- {"query": "894.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1261} 
with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Class,
           row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.TagBased = 0 or b.TagBased is null
),
UserTopBadges as (
    select UserId, DisplayName,
           string_agg(BadgeName || ' (Class ' || Class || ')', ', ') as BadgesList
    from RecursiveUserBadges
    where rn <= 5
    group by UserId, DisplayName
),
PostActivityCTE as (
    select p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId,
        coalesce(p.Score,0) as Score,
        coalesce(p.ViewCount,0) as Views,
        p.Tags,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (4,5,6)) over (partition by p.Id) as EditCount,
        max(ph.CreationDate) over (partition by p.Id) as LastEdit,
        rank() over (partition by p.PostTypeId order by p.Score desc nulls last, p.ViewCount desc nulls last) as PostRank
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    where p.PostTypeId in (1,2)
),
TopQuestions as (
    select Id, OwnerUserId, Score, Views, Tags
    from PostActivityCTE
    where PostTypeId=1 and PostRank <= 50
),
AnswersWithDupes as (
    select a.Id, a.ParentId, a.OwnerUserId, a.Score,
           pl.LinkTypeId, pl.RelatedPostId
    from PostActivityCTE a
    left join PostLinks pl on pl.PostId = a.Id and pl.LinkTypeId = 3
    where a.PostTypeId=2
),
UserAnswerStats as (
    select a.OwnerUserId as UserId,
           count(*) as TotalAnswers,
           count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicateAnswersCount,
           avg(a.Score) as AvgAnswerScore
    from AnswersWithDupes a
    left join PostLinks pl on pl.PostId = a.Id and pl.LinkTypeId = 3
    group by a.OwnerUserId
),
UserQuestionStats as (
    select q.OwnerUserId as UserId,
           count(*) as TotalQuestions,
           avg(q.Score) as AvgQuestionScore,
           bool_or(q.Tags is null or length(trim(q.Tags))=0) as HasUntaggedQuestions
    from TopQuestions q
    group by q.OwnerUserId
),
UserCombinedStats as (
    select u.Id as UserId,
           u.DisplayName,
           us.TotalQuestions,
           us.AvgQuestionScore,
           ua.TotalAnswers,
           ua.AvgAnswerScore,
           ua.DuplicateAnswersCount,
           us.HasUntaggedQuestions,
           utb.BadgesList
    from Users u
    left join UserQuestionStats us on us.UserId = u.Id
    left join UserAnswerStats ua on ua.UserId = u.Id
    left join UserTopBadges utb on utb.UserId = u.Id
),
UserActivityRanked as (
    select *,
           dense_rank() over (order by coalesce(TotalQuestions,0) + coalesce(TotalAnswers,0) desc, coalesce(AvgQuestionScore,0) desc) as ActivityRank
    from UserCombinedStats
),
LatestCloseReasons as (
    select ph.PostId,
           max(ph.CreationDate) as LastCloseDate,
           max(c.Name) as LastCloseReason
    from PostHistory ph
    left join CloseReasonTypes c on c.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
)
select uar.UserId, uar.DisplayName,
       uar.TotalQuestions, uar.AvgQuestionScore,
       uar.TotalAnswers, uar.AvgAnswerScore,
       uar.DuplicateAnswersCount,
       uar.HasUntaggedQuestions,
       uar.BadgesList,
       uar.ActivityRank,
       coalesce(pcq.CloseCount,0) as QuestionsClosed,
       coalesce(pcq.DuplicateCount,0) as QuestionsClosedAsDuplicate,
       coalesce(pcq.OffTopicCount,0) as QuestionsClosedAsOffTopic,
       coalesce(pcq.OtherCloseCount,0) as QuestionsClosedOther,
       lcr.LastCloseDate, lcr.LastCloseReason
from UserActivityRanked uar
left join (
    select p.OwnerUserId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseCount,
        count(*) filter (where ph.PostHistoryTypeId = 10 and ph.Comment in ('1','101')) as DuplicateCount,
        count(*) filter (where ph.PostHistoryTypeId = 10 and ph.Comment in ('2','102')) as OffTopicCount,
        count(*) filter (where ph.PostHistoryTypeId = 10 and ph.Comment not in ('1','101','2','102')) as OtherCloseCount
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    where p.PostTypeId = 1
    group by p.OwnerUserId
) pcq on pcq.OwnerUserId = uar.UserId
left join LatestCloseReasons lcr on lcr.PostId = (
    select p.Id from Posts p
    where p.OwnerUserId = uar.UserId and p.PostTypeId = 1 and p.ClosedDate is not null
    order by p.ClosedDate desc limit 1
)
where (uar.TotalQuestions + uar.TotalAnswers) > 10
order by uar.ActivityRank, uar.DisplayName;