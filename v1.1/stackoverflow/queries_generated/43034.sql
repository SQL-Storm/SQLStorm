-- {"query": "43034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 562} 

WITH TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY u.Id
    HAVING COUNT(DISTINCT p.Id) > 10
    ORDER BY u.Reputation DESC
    LIMIT 100
),
UserActivity AS (
    SELECT 
        ph.UserId,
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId BETWEEN 4 AND 6 THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId BETWEEN 10 AND 15 THEN 1 END) AS ModerationActionCount
    FROM PostHistory ph
    WHERE ph.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY ph.UserId, ph.PostId
),
TopEditedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        SUM(COALESCE(ua.EditCount, 0)) AS TotalEdits,
        SUM(COALESCE(ua.ModerationActionCount, 0)) AS TotalModerationActions
    FROM Posts p
    LEFT JOIN UserActivity ua ON p.Id = ua.PostId
    WHERE p.PostTypeId = 1 AND p.Score > 10
    GROUP BY p.Id
    ORDER BY TotalEdits DESC, TotalModerationActions DESC
    LIMIT 50
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    tu.BadgeCount,
    tu.PostCount,
    tu.TotalQuestionViews,
    tep.Title AS TopEditedPostTitle,
    tep.TotalEdits,
    tep.TotalModerationActions
FROM TopUsers tu
JOIN TopEditedPosts tep ON tu.Id = tep.OwnerUserId
ORDER BY tu.Reputation DESC, tep.TotalEdits DESC;
