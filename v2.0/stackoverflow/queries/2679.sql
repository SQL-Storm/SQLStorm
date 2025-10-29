-- {"query": "2679.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1189}
with recursive UserActivity AS (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(u.Views,0) as Views,
        coalesce(u.UpVotes,0) as UpVotes,
        coalesce(u.DownVotes,0) as DownVotes,
        1 as Level
    from Users u
    where u.Reputation > 1000 and u.Location is not null

    union all

    select
        u2.Id,
        u2.DisplayName,
        u2.Reputation,
        u2.CreationDate,
        u2.Location,
        coalesce(u2.Views,0),
        coalesce(u2.UpVotes,0),
        coalesce(u2.DownVotes,0),
        ua.Level + 1
    from Users u2
    join UserActivity ua on u2.Id = ua.Id + 1
    where ua.Level < 3
),
LatestPostEdits AS (
    select ph.PostId, max(ph.CreationDate) as LastEdit
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.PostId
),
UserBadgesRanked AS (
    select b.UserId, b.Name, b.Class,
        row_number() over (partition by b.UserId order by b.Class asc, b.Date desc) as rn
    from Badges b
),
QuestionAnswerCounts AS (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(qac.AnswerCnt,0) as ActualAnswerCount,
        p.AcceptedAnswerId
    from Posts p
    left join (
        select ParentId, count(*) as AnswerCnt from Posts where PostTypeId = 2 group by ParentId
    ) qac on qac.ParentId = p.Id
    where p.PostTypeId = 1
),
DuplicateQuestions AS (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
QuestionDuplicatesCount AS (
    select dq.PostId, count(*) as DuplicateCount
    from DuplicateQuestions dq
    group by dq.PostId
),
TopTags AS (
    select 
      t.TagName,
      t.Count,
      t.WikiPostId,
      t.ExcerptPostId
    from Tags t
    left join Posts tsw on tsw.Id = t.WikiPostId
    left join Posts tse on tse.Id = t.ExcerptPostId
    where t.Count > 1000
    order by t.Count desc
    limit 50
),
UserTopTagBadgeCount AS (
    select b.UserId, count(*) as TopTagBadgeCount
    from Badges b
    join TopTags tt on b.Name = tt.TagName and (CASE WHEN b.TagBased IS TRUE THEN 1 WHEN b.TagBased IS FALSE THEN 0 ELSE NULL END) = 1
    group by b.UserId
),
ComplexAggregates AS (
    select 
        qa.OwnerUserId,
        count(qa.Id) as TotalQuestions,
        sum(qa.Score) as TotalQuestionScore,
        sum(case when qa.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAcceptedAnswer,
        avg(qa.ViewCount) as AvgViews,
        avg(qa.AnswerCount) as AvgAnswerCount,
        max(qa.AnswerCount - qa.ActualAnswerCount) as MaxDiscrepancyInAnswerCount,
        coalesce(qdc.DuplicateCount,0) as DuplicateCount
    from QuestionAnswerCounts qa
    left join QuestionDuplicatesCount qdc on qdc.PostId = qa.Id
    group by qa.OwnerUserId, qdc.DuplicateCount
),
RankedUsers AS (
    select 
        ua.Id,
        ua.DisplayName,
        ca.TotalQuestions,
        ca.TotalQuestionScore,
        ca.QuestionsWithAcceptedAnswer,
        ca.AvgViews,
        ca.AvgAnswerCount,
        ca.MaxDiscrepancyInAnswerCount,
        ub.TopTagBadgeCount,
        ua.Reputation,
        row_number() over (
            order by ca.TotalQuestionScore desc NULLS LAST, ua.Reputation desc NULLS LAST
        ) as UserRank
    from UserActivity ua
    left join ComplexAggregates ca on ca.OwnerUserId = ua.Id
    left join UserTopTagBadgeCount ub on ub.UserId = ua.Id
    where coalesce(ca.TotalQuestions,0) > 10
)
select 
    ru.UserRank,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalQuestions,
    ru.TotalQuestionScore,
    ru.QuestionsWithAcceptedAnswer,
    ru.AvgViews,
    ru.AvgAnswerCount,
    coalesce(ru.MaxDiscrepancyInAnswerCount,0) as MaxDiscrepancyInAnswerCount,
    coalesce(ru.TopTagBadgeCount,0) as TopTagBadgeCount,
    concat(
        case when ru.AvgViews > 10000 then 'Popular Author' else 'Normal Author' end,
        ' | ',
        case when (ru.QuestionsWithAcceptedAnswer * 1.0) / ru.TotalQuestions > 0.5 then 'Helpful' else 'Unhelpful' end
    ) as AuthorProfile,
    case 
        when ru.UserRank <= 10 then 'Top 10'
        when ru.UserRank <= 50 then 'Top 50'
        else 'Other'
    end as UserTier
from RankedUsers ru
where ru.UserRank <= 100
order by ru.UserRank;