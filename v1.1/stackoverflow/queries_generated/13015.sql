-- {"query": "13015.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 563} 

WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, 
           COUNT(DISTINCT b.Id) AS BadgeCount,
           DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.DisplayName) AS UserRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation IS NOT NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostMetrics AS (
    SELECT p.OwnerUserId, 
           SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
           SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScores,
           COUNT(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 END) AS AcceptedAnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentActivity AS (
    SELECT ph.UserId, 
           MAX(ph.CreationDate) AS LastActivityDate,
           STRING_AGG(DISTINCT crt.Name, ', ') WITHIN GROUP (ORDER BY crt.Name) AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS smallint) = crt.Id
    WHERE ph.PostHistoryTypeId IN (10, 11) AND ph.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
    GROUP BY ph.UserId
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    pm.TotalQuestionViews,
    pm.TotalAnswerScores,
    pm.AcceptedAnswerCount,
    ra.LastActivityDate,
    COALESCE(ra.CloseReasons, 'No Recent Close Activities') AS RecentCloseReasons,
    CONCAT(tu.BadgeCount, ' badges') AS BadgeSummary,
    NTILE(4) OVER (ORDER BY pm.TotalAnswerScores DESC NULLS LAST) AS AnswerScoreQuartile
FROM TopUsers tu
LEFT JOIN PostMetrics pm ON tu.Id = pm.OwnerUserId
LEFT JOIN RecentActivity ra ON tu.Id = ra.UserId
WHERE tu.UserRank <= 100
ORDER BY tu.UserRank, pm.TotalAnswerScores DESC;
