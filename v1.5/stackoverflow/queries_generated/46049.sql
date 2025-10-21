-- {"query": "46049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 112406, "output_tokens": 91484} 

WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
        AND p.Score > 5
    GROUP BY p.OwnerUserId, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswererId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        AVG(a.Score) as AvgAnswerScore,
        MAX(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) as HasAcceptedAnswer
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY a.ParentId, a.OwnerUserId
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as BronzeBadges,
        COUNT(CASE WHEN b.TagBased = 1 THEN 1 END) as TagBasedBadges
    FROM Badges b
    WHERE b.Date >= TIMESTAMP '2019-01-01'
    GROUP BY b.UserId
),
InteractionGraph AS (
    SELECT 
        p.OwnerUserId as QuestionOwnerId,
        a.OwnerUserId as AnswererId,
        COUNT(DISTINCT p.Id) as InteractionCount,
        AVG(a.Score) as AvgInteractionScore,
        SUM(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) as AcceptedCount
    FROM Posts p
    INNER JOIN Posts a ON p.Id = a.ParentId
    WHERE p.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND p.OwnerUserId IS NOT NULL
        AND a.OwnerUserId IS NOT NULL
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY p.OwnerUserId, a.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 3
)
SELECT 
    tqa.DisplayName as AuthorName,
    tqa.QuestionCount,
    tqa.AvgScore as AvgQuestionScore,
    tqa.TotalViews,
    COALESCE(ubs.GoldBadges, 0) as GoldBadges,
    COALESCE(ubs.SilverBadges, 0) as SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) as BronzeBadges,
    COUNT(DISTINCT am.AnswererId) as UniqueAnswerers,
    AVG(am.AvgAnswerScore) as AvgAnswerScoreOnQuestions,
    SUM(am.HasAcceptedAnswer) as QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT ig.AnswererId) as RecurringAnswerers,
    AVG(ig.AvgInteractionScore) as AvgRecurringAnswererScore,
    SUM(ig.AcceptedCount) as RecurringAcceptedAnswers,
    COALESCE(SUM(v.BountyAmount), 0) as TotalBountiesOffered,
    COUNT(DISTINCT c.Id) as TotalCommentsReceived,
    AVG(c.Score) as AvgCommentScore
FROM TopQuestionAuthors tqa
LEFT JOIN AnswerMetrics am ON am.QuestionId IN (
    SELECT Id FROM Posts WHERE OwnerUserId = tqa.OwnerUserId AND PostTypeId = 1
)
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = tqa.OwnerUserId
LEFT JOIN InteractionGraph ig ON ig.QuestionOwnerId = tqa.OwnerUserId
LEFT JOIN Posts p ON p.OwnerUserId = tqa.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8
LEFT JOIN Comments c ON c.PostId = p.Id
GROUP BY 
    tqa.OwnerUserId,
    tqa.DisplayName,
    tqa.QuestionCount,
    tqa.AvgScore,
    tqa.TotalViews,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges
HAVING COUNT(DISTINCT am.AnswererId) >= 5
ORDER BY 
    (tqa.QuestionCount * 0.3 + 
     COALESCE(ubs.GoldBadges, 0) * 10 + 
     COUNT(DISTINCT ig.AnswererId) * 0.5) DESC
LIMIT 100;
