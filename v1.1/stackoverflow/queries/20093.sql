WITH UserQuestionStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalQuestions,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalQuestionViews,
        SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswersOnQuestions,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(p.Id) AS AcceptedAnswerRate,
        STRING_AGG(
            DISTINCT (string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags)-2)), '><'))[1],
            ', '
        ) AS PrimaryTagsSample
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND u.Reputation > 1000
      AND p.CreationDate > DATE '2015-01-01'
      AND p.ClosedDate IS NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 10
),
UserAnswerStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(COALESCE(p.CommentCount, 0)) AS TotalCommentsOnAnswers,
        (
         SELECT COUNT(*)
         FROM Posts a
         JOIN Posts q ON a.ParentId = q.Id
         WHERE a.OwnerUserId = p.OwnerUserId
           AND q.ViewCount > 10000
           AND a.PostTypeId = 2
        ) AS AnswersOnPopularQuestions
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IN (SELECT OwnerUserId FROM UserQuestionStats)
    GROUP BY p.OwnerUserId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        uqs.TotalQuestions,
        uas.TotalAnswers,
        uqs.AvgQuestionScore,
        uas.AvgAnswerScore,
        uqs.TotalQuestionViews,
        uqs.AcceptedAnswerRate,
        uas.AnswersOnPopularQuestions,
        uqs.PrimaryTagsSample,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS RankInCohort
    FROM Users u
    JOIN UserQuestionStats uqs ON u.Id = uqs.OwnerUserId
    LEFT JOIN UserAnswerStats uas ON u.Id = uas.OwnerUserId
    WHERE u.DisplayName NOT LIKE 'user%' AND u.AboutMe IS NOT NULL
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.RankInCohort,
    (ue.TotalQuestions + COALESCE(ue.TotalAnswers, 0)) AS TotalContributions,
    CAST(ue.TotalQuestionViews AS DOUBLE PRECISION) / (ue.TotalQuestions + 1) AS AvgViewsPerQuestion,
    (ue.AvgQuestionScore * ue.TotalQuestions + COALESCE(ue.AvgAnswerScore, 0) * COALESCE(ue.TotalAnswers, 0)) / (ue.TotalQuestions + COALESCE(ue.TotalAnswers, 0) + 1) AS WeightedAvgScore,
    ue.AcceptedAnswerRate,
    ue.AnswersOnPopularQuestions,
    CASE
      WHEN ue.PrimaryTagsSample IS NULL OR ue.PrimaryTagsSample = '' THEN 0
      ELSE LENGTH(ue.PrimaryTagsSample) - LENGTH(REPLACE(ue.PrimaryTagsSample, ',', '')) + 1
    END AS DistinctPrimaryTags,
    (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = ue.UserId AND b.Class = 1
    ) AS GoldBadges
FROM UserEngagement ue

UNION ALL

SELECT
    -v.UserId AS UserId,
    ('TopVoter ' || u.DisplayName) AS DisplayName,
    u.Reputation,
    999 AS RankInCohort,
    NULL AS TotalContributions,
    NULL AS AvgViewsPerQuestion,
    AVG(p.Score) AS WeightedAvgScore,
    NULL AS AcceptedAnswerRate,
    NULL AS AnswersOnPopularQuestions,
    NULL AS DistinctPrimaryTags,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS GoldBadges
FROM Votes v
JOIN Users u ON v.UserId = u.Id
JOIN Posts p ON v.PostId = p.Id
WHERE v.UserId IS NOT NULL AND v.VoteTypeId IN (2,3)
GROUP BY v.UserId, u.DisplayName, u.Reputation
HAVING COUNT(v.Id) > 5000 AND AVG(p.Score) < 5

ORDER BY Reputation DESC, WeightedAvgScore DESC NULLS LAST
LIMIT 200;