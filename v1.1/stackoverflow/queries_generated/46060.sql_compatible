WITH RECURSIVE UserHierarchy AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        1 AS Level
    FROM Users u
    WHERE u.Reputation > 10000

    UNION ALL

    SELECT 
        u2.Id,
        u2.DisplayName,
        u2.Reputation,
        u2.CreationDate,
        uh.Level + 1
    FROM Users u2
    INNER JOIN Comments c ON u2.Id = c.UserId
    INNER JOIN Posts p ON c.PostId = p.Id
    INNER JOIN UserHierarchy uh ON p.OwnerUserId = uh.Id
    WHERE uh.Level < 3 AND u2.Reputation > 5000
),
TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        ARRAY_AGG(DISTINCT SUBSTRING(t.tag, 1, 20)) FILTER (WHERE t.tag IS NOT NULL) AS TopTags
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    ) t ON true
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
        AND p.Score > 5
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 5
),
AnswerMetrics AS (
    SELECT 
        a.OwnerUserId AS AnswererUserId,
        q.OwnerUserId AS QuestionerUserId,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Id END) AS AcceptedCount,
        AVG(a.Score) AS AvgAnswerScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) AS MedianScore,
        MAX(a.Score) AS MaxScore
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
        AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '18 months'
        AND q.PostTypeId = 1
    GROUP BY a.OwnerUserId, q.OwnerUserId
),
BadgeProgress AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) AS BadgeNames,
        MIN(b.Date) AS FirstBadge,
        MAX(b.Date) AS LatestBadge
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY b.UserId, b.Class
),
CommentEngagement AS (
    SELECT 
        c.UserId,
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY c.UserId, c.PostId
)
SELECT 
    uh.DisplayName,
    uh.Reputation,
    uh.Level AS InteractionLevel,
    COALESCE(tqa.QuestionCount, 0) AS TotalQuestions,
    COALESCE(tqa.AvgScore, 0) AS AvgQuestionScore,
    COALESCE(tqa.TotalViews, 0) AS TotalQuestionViews,
    COALESCE(am.AnswerCount, 0) AS TotalAnswers,
    COALESCE(am.AcceptedCount, 0) AS AcceptedAnswers,
    COALESCE(am.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(am.MedianScore, 0) AS MedianAnswerScore,
    COALESCE(bp_gold.BadgeCount, 0) AS GoldBadges,
    COALESCE(bp_silver.BadgeCount, 0) AS SilverBadges,
    COALESCE(bp_bronze.BadgeCount, 0) AS BronzeBadges,
    COALESCE(ce.CommentCount, 0) AS RecentComments,
    COALESCE(ce.AvgCommentScore, 0) AS AvgCommentScore,
    ROUND(
        (COALESCE(tqa.AvgScore, 0) * 0.3 + 
         COALESCE(am.AvgAnswerScore, 0) * 0.3 + 
         COALESCE(CAST(am.AcceptedCount AS numeric) / NULLIF(am.AnswerCount, 0), 0) * 100 * 0.2 +
         COALESCE(bp_gold.BadgeCount, 0) * 0.1 +
         COALESCE(ce.AvgCommentScore, 0) * 0.1), 2
    ) AS EngagementScore,
    tqa.TopTags AS PreferredTags,
    DENSE_RANK() OVER (ORDER BY COALESCE(tqa.QuestionCount, 0) + COALESCE(am.AnswerCount, 0) DESC) AS ActivityRank,
    ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM uh.CreationDate) ORDER BY uh.Reputation DESC) AS CohortRank,
    uh.Id,
    uh.CreationDate
FROM UserHierarchy uh
LEFT JOIN TopQuestionAuthors tqa ON uh.Id = tqa.OwnerUserId
LEFT JOIN AnswerMetrics am ON uh.Id = am.AnswererUserId
LEFT JOIN BadgeProgress bp_gold ON uh.Id = bp_gold.UserId AND bp_gold.Class = 1
LEFT JOIN BadgeProgress bp_silver ON uh.Id = bp_silver.UserId AND bp_silver.Class = 2
LEFT JOIN BadgeProgress bp_bronze ON uh.Id = bp_bronze.UserId AND bp_bronze.Class = 3
LEFT JOIN (
    SELECT UserId, SUM(CommentCount) AS CommentCount, AVG(AvgCommentScore) AS AvgCommentScore
    FROM CommentEngagement
    GROUP BY UserId
) ce ON uh.Id = ce.UserId
WHERE uh.Level <= 2
    AND (tqa.QuestionCount IS NOT NULL OR am.AnswerCount IS NOT NULL)
ORDER BY EngagementScore DESC, uh.Reputation DESC
LIMIT 100;