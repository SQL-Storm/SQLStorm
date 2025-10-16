WITH TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName, u.Reputation
), 
QuestionMetrics AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserTopQuestionRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
AnswerMetrics AS (
    SELECT 
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        COUNT(*) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId, p.OwnerUserId
),
CombinedMetrics AS (
    SELECT
        qm.Id AS QuestionId,
        qm.OwnerUserId,
        qm.CreationDate,
        qm.Score,
        qm.ViewCount,
        qm.AnswerCount AS QuestionAnswerCount,
        qm.CommentCount,
        qm.FavoriteCount,
        am.AnswerCount AS AnswerMetricsAnswerCount,
        am.AvgAnswerScore,
        COALESCE(am.AnswerCount, 0) + COALESCE(qm.AnswerCount, 0) AS TotalInteractions
    FROM QuestionMetrics qm
    LEFT JOIN AnswerMetrics am ON qm.Id = am.QuestionId AND qm.OwnerUserId = am.OwnerUserId
    WHERE qm.UserTopQuestionRank <= 5
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    tu.TotalBadges,
    tu.GoldBadges,
    cm.QuestionId,
    cm.CreationDate,
    cm.Score,
    cm.ViewCount,
    cm.QuestionAnswerCount AS AnswerCount,
    cm.CommentCount,
    cm.FavoriteCount,
    cm.AvgAnswerScore,
    cm.TotalInteractions,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cm.QuestionId AND c.Score > 0) AS PositiveCommentCount,
    CASE 
        WHEN cm.TotalInteractions > 100 THEN 'High Interaction'
        WHEN cm.TotalInteractions BETWEEN 50 AND 100 THEN 'Medium Interaction'
        ELSE 'Low Interaction'
    END AS InteractionCategory
FROM TopUsers tu
JOIN CombinedMetrics cm ON tu.Id = cm.OwnerUserId
WHERE tu.ReputationRank <= 10
GROUP BY
    tu.DisplayName,
    tu.Reputation,
    tu.TotalBadges,
    tu.GoldBadges,
    cm.QuestionId,
    cm.CreationDate,
    cm.Score,
    cm.ViewCount,
    cm.QuestionAnswerCount,
    cm.CommentCount,
    cm.FavoriteCount,
    cm.AvgAnswerScore,
    cm.TotalInteractions
ORDER BY cm.TotalInteractions DESC, tu.Reputation DESC
LIMIT 50;