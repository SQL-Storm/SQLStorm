-- {"query": "22039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1031} 
WITH QuestionMetrics AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        LENGTH(COALESCE(p.Body, '')) AS BodyLength,
        CASE WHEN p.Tags IS NULL THEN 0 ELSE array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) END AS TagCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (8,9)) AS TotalBounties
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AnswerMetrics AS (
    SELECT 
        p.Id,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.AcceptedAnswerId,
        COALESCE(AVG(vt.Score), 0) AS AvgCommentScore -- Correlated subquery here?
    FROM Posts p
    LEFT JOIN Comments vt ON vt.PostId = p.Id -- wait, Comments has Score
    WHERE p.PostTypeId = 2
    GROUP BY p.Id, p.ParentId, p.OwnerUserId, p.Score, p.AcceptedAnswerId
),
UserPostStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT qm.Id) AS TotalQuestions,
        COUNT(DISTINCT am.Id) AS TotalAnswers,
        COALESCE(SUM(qm.Score), 0) AS TotalQuestionScore,
        COALESCE(SUM(am.Score), 0) AS TotalAnswerScore,
        COALESCE(SUM(qm.ViewCount), 0) AS TotalViews,
        COALESCE(SUM(qm.CommentCount), 0) AS TotalComments,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeList
    FROM Users u
    LEFT JOIN QuestionMetrics qm ON u.Id = qm.OwnerUserId
    LEFT JOIN AnswerMetrics am ON u.Id = am.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND u.LastAccessDate > '2020-01-01'::timestamp
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY (TotalQuestionScore + TotalAnswerScore + TotalViews * 0.01 + TotalComments * 10 + GoldBadges * 100) DESC) AS OverallRank,
        RANK() OVER (PARTITION BY TotalBadges ORDER BY Reputation DESC) AS RepRankPerBadge,
        DENSE_RANK() OVER (ORDER BY TotalAnswers DESC) AS AnswerRank
    FROM UserPostStats
),
DetailedPostAnalysis AS (
    SELECT 
        qm.Id AS QuestionId,
        qm.OwnerUserId,
        am.Id AS AnswerId,
        am.OwnerUserId AS AnswerOwnerId,
        qm.Score AS QScore,
        am.Score AS AScore,
        CASE WHEN qm.AcceptedAnswerId = am.Id THEN 1 ELSE 0 END AS IsAccepted,
        qm.BodyLength,
        qm.TagCount,
        qm.TotalBounties,
        NULLIF(qm.ViewCount, 0) / NULLIF(qm.AnswerCount, 0) AS ViewsPerAnswer,
        SUBSTRING(LOWER(qm.Title), 1, 50) || '...' AS ShortTitle,
        am.AvgCommentScore
    FROM QuestionMetrics qm
    FULL OUTER JOIN AnswerMetrics am ON qm.Id = am.ParentId
    WHERE (qm.Score > 10 OR am.Score > 5) AND (qm.Tags LIKE '%sql%' OR qm.Tags LIKE '%database%')
)
SELECT ru.Id, ru.DisplayName, ru.Reputation, ru.TotalQuestions, ru.TotalAnswers, ru.TotalQuestionScore, ru.TotalAnswerScore, ru.TotalViews, ru.TotalComments, ru.TotalBadges, ru.GoldBadges, ru.OverallRank, ru.RepRankPerBadge, ru.AnswerRank
FROM RankedUsers ru
WHERE ru.OverallRank <= 100
UNION ALL
SELECT NULL, 'Average Stats', AVG(ru.Reputation), AVG(ru.TotalQuestions), AVG(ru.TotalAnswers), AVG(ru.TotalQuestionScore), AVG(ru.TotalAnswerScore), AVG(ru.TotalViews), AVG(ru.TotalComments), AVG(ru.TotalBadges), AVG(ru.GoldBadges), NULL, NULL, NULL
FROM RankedUsers ru
ORDER BY OverallRank NULLS LAST;