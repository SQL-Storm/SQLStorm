WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS rn_activity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE u.DisplayName IS NOT NULL
      AND u.Reputation > 1000
      AND p.PostTypeId IN (1, 2)
),
UserPostStats AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        COUNT(CASE WHEN PostType = 'Question' THEN PostId END) AS QuestionCount,
        SUM(CASE WHEN PostType = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CASE WHEN PostType = 'Question' THEN PostScore END) AS AvgQuestionScore,
        AVG(CASE WHEN PostType = 'Answer' THEN PostScore END) AS AvgAnswerScore,
        MAX(PostScore) AS MaxPostScore,
        SUM(PostScore) AS TotalScore,
        COUNT(DISTINCT PostId) AS TotalPosts
    FROM RankedUserActivity
    GROUP BY UserId, DisplayName, Reputation, UserCreationDate
),
CommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    JOIN Users u ON c.UserId = u.Id
    WHERE u.Reputation > 500
    GROUP BY c.UserId
),
RecentHotQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.ViewCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC, p.ViewCount DESC) AS hot_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '7 day')
      AND p.Score > 100
      AND p.AnswerCount > 5
),
UserEngagement AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.UserCreationDate,
        ups.QuestionCount,
        ups.AnswerCount,
        COALESCE(ca.CommentCount, 0) AS TotalComments,
        COALESCE(ca.PositiveCommentCount, 0) AS PositiveComments,
        COALESCE(ca.AvgCommentScore, 0) AS AvgCommentScore,
        CASE
            WHEN ups.TotalScore > 1000 THEN 'High Performer'
            WHEN ups.TotalScore > 200 THEN 'Mid Performer'
            ELSE 'Standard Performer'
        END AS PerformanceTier
    FROM UserPostStats ups
    LEFT JOIN CommentActivity ca ON ups.UserId = ca.UserId
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.QuestionCount,
    ue.AnswerCount,
    ue.TotalComments,
    ue.PositiveComments,
    ue.AvgCommentScore,
    ue.PerformanceTier,
    rhq.QuestionTitle AS TopHotQuestionTitle,
    rhq.ViewCount AS TopHotQuestionViews,
    CASE
        WHEN ue.Reputation > 10000 AND ue.AnswerCount > 50 THEN 'Elite Contributor'
        WHEN ue.Reputation > 5000 AND ue.QuestionCount > 20 THEN 'Senior Contributor'
        WHEN ue.Reputation > 1000 AND ue.AnswerCount > 10 THEN 'Active Contributor'
        ELSE 'Regular Contributor'
    END AS ContributorLevel,
    UPPER(SUBSTR(ue.DisplayName, 1, 3)) || '-' || RIGHT('000' || CAST(ue.UserId AS VARCHAR), 3) AS UserIdentifier,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ue.UserId AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ue.UserId AND b.Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ue.UserId AND b.Class = 3) AS BronzeBadgeCount,
    CAST(ue.Reputation AS DOUBLE PRECISION) / NULLIF(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - ue.UserCreationDate)) / 86400.0, 0) AS ReputationPerDay,
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = ue.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditsMade,
    CASE WHEN (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ue.UserId AND p2.ClosedDate IS NOT NULL) > 0 THEN 'HasClosedPosts' ELSE 'NoClosedPosts' END AS PostClosureStatus
FROM UserEngagement ue
LEFT JOIN RecentHotQuestions rhq ON rhq.hot_rank = 1
WHERE ue.Reputation BETWEEN 500 AND 20000
  AND ue.UserCreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 day')
ORDER BY ue.Reputation DESC, ue.AnswerCount DESC
LIMIT 100;