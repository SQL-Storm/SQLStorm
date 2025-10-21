-- {"query": "13086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 677} 

WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(DISTINCT b.Id) AS BadgeCount,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserPosts AS (
    SELECT p.OwnerUserId, COUNT(*) AS PostCount, AVG(p.Score) AS AvgScore,
           SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswers
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
CommentMetrics AS (
    SELECT c.UserId, COUNT(*) AS CommentCount, AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    WHERE c.CreationDate >= DATE_TRUNC('year', CURRENT_DATE) - INTERVAL '1 year'
    GROUP BY c.UserId
),
UserActivity AS (
    SELECT ph.UserId, COUNT(*) AS EditCount,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN ph.PostId END) AS InitialPostCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
    GROUP BY ph.UserId
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    tu.BadgeCount,
    COALESCE(up.PostCount, 0) AS PostCount,
    COALESCE(up.AvgScore, 0) AS AvgPostScore,
    COALESCE(up.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(cm.CommentCount, 0) AS CommentCount,
    COALESCE(cm.AvgCommentLength, 0) AS AvgCommentLength,
    COALESCE(ua.EditCount, 0) AS EditCount,
    COALESCE(ua.InitialPostCount, 0) AS InitialPostCount,
    (tu.Reputation + COALESCE(up.PostCount, 0) * 10 + COALESCE(cm.CommentCount, 0) * 2 + COALESCE(ua.EditCount, 0) * 5) AS ActivityScore
FROM TopUsers tu
LEFT JOIN UserPosts up ON tu.Id = up.OwnerUserId
LEFT JOIN CommentMetrics cm ON tu.Id = cm.UserId
LEFT JOIN UserActivity ua ON tu.Id = ua.UserId
WHERE tu.ReputationRank <= 100
ORDER BY ActivityScore DESC
LIMIT 20;
