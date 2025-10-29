-- {"query": "2348.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1488}
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
LatestUserActivity as (
    select
        p.OwnerUserId,
        max(p.LastActivityDate) as LastActivity,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        avg(nullif(p.Score, 0)) as AvgPostScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.ViewCount,
        p.Score,
        p.Tags,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate > (cast('2024-10-01' as date) - interval '180' day) and p.Score > 5
),
TagExploded as (
    select
        q.Id as QuestionId,
        trim(both ' ' from unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags) - 2), '><'))) as SingleTag
    from Posts q
    where q.PostTypeId = 1 and q.Tags is not null and q.Tags <> ''
),
TagStats as (
    select
        te.SingleTag,
        count(distinct te.QuestionId) as QuestionCount,
        avg(q.Score) as AvgQuestionScore
    from TagExploded te
    join Posts q on te.QuestionId = q.Id
    group by te.SingleTag
    having count(distinct te.QuestionId) > 10
),
UserAnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2 and a.Score is not null
),
ClosedQuestionsAndReasons as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    inner join CloseReasonTypes cr on cast(ph.Comment as integer) = cr.Id
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(lua.QuestionCount, 0) as QuestionCount,
        coalesce(lua.AnswerCount, 0) as AnswerCount,
        coalesce(lua.AvgPostScore, 0) as AveragePostScore,
        coalesce(bc.BadgeCount, 0) as BadgeCount,
        coalesce(cq.ClosedCount, 0) as ClosedQuestions
    from Users u
    left join LatestUserActivity lua on u.Id = lua.OwnerUserId
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) bc on u.Id = bc.UserId
    left join (
        select p.OwnerUserId, count(*) as ClosedCount
        from Posts p
        join ClosedQuestionsAndReasons cqa on p.Id = cqa.PostId
        where p.OwnerUserId is not null
        group by p.OwnerUserId
    ) cq on u.Id = cq.OwnerUserId
),
QuestionsWithDuplicates as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Score, q.ViewCount, q.OwnerUserId
),
PopularQuestionsWithAnswerRanks as (
    select
        tq.QuestionId,
        tq.Title,
        tq.Score,
        tq.ViewCount,
        tq.OwnerUserId,
        u.DisplayName as OwnerName,
        ua.AnswerId,
        ua.Score as AnswerScore,
        ua.AnswerRank
    from QuestionsWithDuplicates tq
    join Users u on tq.OwnerUserId = u.Id
    left join UserAnswerRanks ua on ua.QuestionId = tq.QuestionId and ua.AnswerRank <= 3
    where tq.Score > 10 and tq.ViewCount > 1000
),
FinalResult as (
    select
        pqwr.QuestionId,
        pqwr.Title,
        pqwr.Score,
        pqwr.ViewCount,
        pqwr.OwnerUserId,
        pqwr.OwnerName,
        pqwr.AnswerId,
        pqwr.AnswerScore,
        pqwr.AnswerRank,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.BadgeCount,
        ts.SingleTag,
        ts.QuestionCount as TagQuestionCount,
        ts.AvgQuestionScore as TagAvgScore,
        coalesce(cs.CloseReason, 'Open') as CloseReason
    from PopularQuestionsWithAnswerRanks pqwr
    left join UserActivitySummary uas on pqwr.OwnerUserId = uas.UserId
    left join TagExploded te on te.QuestionId = pqwr.QuestionId
    left join TagStats ts on ts.SingleTag = te.SingleTag
    left join ClosedQuestionsAndReasons cs on cs.PostId = pqwr.QuestionId
)
select
    fr.QuestionId,
    fr.Title,
    fr.Score,
    fr.ViewCount,
    fr.OwnerName,
    fr.AnswerId,
    fr.AnswerScore,
    fr.AnswerRank,
    fr.QuestionCount as OwnerQuestionCount,
    fr.AnswerCount as OwnerAnswerCount,
    fr.BadgeCount as OwnerBadgeCount,
    fr.SingleTag,
    fr.TagQuestionCount,
    fr.TagAvgScore,
    fr.CloseReason,
    case 
        when fr.AnswerRank = 1 then 'Top Answer'
        when fr.AnswerRank between 2 and 3 then 'High Ranked Answer'
        else 'Other Answer'
    end as AnswerCategory,
    length(fr.Title) + fr.Score * 7 - coalesce(fr.TagQuestionCount,0) as CustomScoreCalculation,
    case 
        when fr.CloseReason is null then false
        else true
    end as IsClosed
from FinalResult fr
where fr.TagAvgScore > 2.0
order by CustomScoreCalculation desc, fr.ViewCount desc
limit 100;