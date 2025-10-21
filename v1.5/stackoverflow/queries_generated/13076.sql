-- {"query": "13076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 615} 

WITH UserActivity AS (
    SELECT 
        UserId,
        COUNT(DISTINCT PostId) AS TotalPosts,
        SUM(Score) AS TotalScore,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN PostId END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN PostId END) AS TotalAnswers,
        MAX(CreationDate) AS LastPostDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY UserId
),
HighReputationUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        STRING_AGG(b.Name, ', ') AS BadgesEarned
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
TopPostEditors AS (
    SELECT 
        ph.UserId,
        COUNT(*) AS EditCount,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS EditRank
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.UserId
),
CombinedResults AS (
    SELECT 
        h.UserId,
        h.DisplayName,
        h.Reputation,
        h.Location,
        h.BadgesEarned,
        ua.TotalPosts,
        ua.TotalScore,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.LastPostDate,
        te.EditCount
    FROM HighReputationUsers h
    JOIN UserActivity ua ON h.UserId = ua.UserId
    LEFT JOIN TopPostEditors te ON h.UserId = te.UserId AND te.EditRank <= 10
)
SELECT 
    c.UserId,
    c.DisplayName,
    c.Reputation,
    COALESCE(NULLIF(c.Location, ''), 'Unknown') AS Location,
    c.BadgesEarned,
    c.TotalPosts,
    c.TotalScore,
    c.TotalQuestions,
    c.TotalAnswers,
    c.LastPostDate,
    COALESCE(c.EditCount, 0) AS EditCount,
    ROW_NUMBER() OVER (ORDER BY c.Reputation DESC, c.TotalScore DESC) AS PerformanceRank
FROM CombinedResults c
WHERE c.TotalPosts > (
    SELECT AVG(TotalPosts)
    FROM UserActivity
)
ORDER BY PerformanceRank;
