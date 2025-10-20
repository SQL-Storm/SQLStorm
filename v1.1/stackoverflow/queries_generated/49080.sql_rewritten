-- {"query": "49080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1634} 
WITH GoldBadgeOwners AS (
    SELECT DISTINCT UserId
    FROM Badges
    WHERE Class = 1 -- Gold badges
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p_q.Id) AS TotalQuestions,
        SUM(p_q.Score) AS TotalQuestionScore,
        SUM(p_q.ViewCount) AS TotalQuestionViews,
        AVG(p_q.Score) AS AvgQuestionScore,
        AVG(p_q.ViewCount) AS AvgQuestionViewCount,
        COUNT(DISTINCT p_a.Id) AS TotalAnswers,
        SUM(p_a.Score) AS TotalAnswerScore,
        AVG(p_a.Score) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN p_a.Id = q_parent.AcceptedAnswerId THEN p_a.Id ELSE NULL END) AS AcceptedAnswersCount,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        AVG(c.Score) AS AvgCommentScoreMade,
        COUNT(DISTINCT ph.Id) AS TotalPostHistoryEventsOnOwnPosts,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditsOnOwnPosts -- Edit Title, Body, Tags
    FROM Users u
    LEFT JOIN Posts p_q ON u.Id = p_q.OwnerUserId AND p_q.PostTypeId = 1 AND p_q.CreationDate >= '2015-01-01'
    LEFT JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2 AND p_a.CreationDate >= '2015-01-01'
    LEFT JOIN Posts q_parent ON p_a.ParentId = q_parent.Id
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= '2015-01-01'
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.CreationDate >= '2015-01-01'
                             AND (ph.PostId = p_q.Id OR ph.PostId = p_a.Id)
    WHERE u.CreationDate >= '2014-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p_q.Id) > 0 AND COUNT(DISTINCT p_a.Id) > 0
),
TagSpecificQuestionStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TaggedQuestionCount,
        AVG(p.Score) AS AvgTaggedQuestionScore,
        AVG(p.ViewCount) AS AvgTaggedQuestionViewCount,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedTaggedQuestions
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<database>%')
      AND p.CreationDate >= '2015-01-01'
    GROUP BY p.OwnerUserId
),
GlobalAverages AS (
    SELECT
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1 AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<database>%')) AS GlobalAvgTaggedQuestionScore,
        AVG(p.ViewCount) FILTER (WHERE p.PostTypeId = 1 AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<database>%')) AS GlobalAvgTaggedQuestionViewCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS GlobalAvgAnswerScore,
        COUNT(CASE WHEN p.PostTypeId = 2 AND p.AcceptedAnswerId IS NOT NULL THEN 1 END) * 1.0 / NULLIF(COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END), 0) AS GlobalAnswerAcceptanceRate
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalQuestions,
    uas.TotalAnswers,
    tqss.TaggedQuestionCount,
    tqss.AvgTaggedQuestionScore,
    tqss.AvgTaggedQuestionViewCount,
    uas.AvgAnswerScore,
    uas.AcceptedAnswersCount,
    uas.TotalCommentsMade,
    uas.AvgCommentScoreMade,
    uas.TotalEditsOnOwnPosts,
    COALESCE(tqss.AvgTaggedQuestionScore / ga.GlobalAvgTaggedQuestionScore, 0) AS TaggedQuestionScoreRatio,
    COALESCE(tqss.AvgTaggedQuestionViewCount / ga.GlobalAvgTaggedQuestionViewCount, 0) AS TaggedQuestionViewRatio,
    COALESCE(uas.AvgAnswerScore / ga.GlobalAvgAnswerScore, 0) AS AnswerScoreRatio,
    (
        COALESCE(tqss.AvgTaggedQuestionScore * 0.4, 0) +
        COALESCE(tqss.AvgTaggedQuestionViewCount * 0.001 * 0.2, 0) +
        COALESCE(uas.AvgAnswerScore * 0.3, 0) +
        COALESCE(uas.AcceptedAnswersCount * 10 * 0.1, 0) +
        COALESCE(uas.TotalEditsOnOwnPosts * 0.05, 0)
    ) AS CompositeContentScore,
    RANK() OVER (ORDER BY (
        uas.Reputation * 0.5 +
        (COALESCE(tqss.AvgTaggedQuestionScore, 0) + COALESCE(tqss.AvgTaggedQuestionViewCount / 100, 0)) * 0.2 +
        COALESCE(uas.AvgAnswerScore, 0) * 0.2 +
        COALESCE(uas.AcceptedAnswersCount * 5, 0) +
        COALESCE(uas.TotalCommentsMade / 10, 0) +
        COALESCE(uas.TotalEditsOnOwnPosts / 5, 0)
    ) DESC) AS OverallUserRank
FROM UserActivitySummary uas
JOIN GoldBadgeOwners gbo ON uas.UserId = gbo.UserId
LEFT JOIN TagSpecificQuestionStats tqss ON uas.UserId = tqss.UserId
CROSS JOIN GlobalAverages ga
WHERE uas.Reputation >= 10000
  AND uas.TotalQuestions >= 5
  AND uas.TotalAnswers >= 10
  AND COALESCE(tqss.TaggedQuestionCount, 0) >= 2
ORDER BY OverallUserRank ASC, CompositeContentScore DESC
LIMIT 100;