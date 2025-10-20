-- {"query": "28064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1693} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS Location,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 8)
    WHERE u.CreationDate >= '2015-01-01'
    GROUP BY u.Id, u.DisplayName, u.Location, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10 OR COUNT(DISTINCT c.Id) > 50
),
GoldBadgeUsers AS (
    SELECT 
        UserId,
        COUNT(*) AS GoldBadges,
        MAX(Date) AS LastGoldBadgeDate
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
),
PostClosures AS (
    SELECT 
        PostId,
        COUNT(*) AS ClosureCount,
        STRING_AGG(COALESCE(ph.Comment, 'Manual'), ', ') AS CloseReasons
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    AND EXISTS (
        SELECT 1 
        FROM CloseReasonTypes crt 
        WHERE crt.Id = CAST(ph.Comment AS INTEGER) 
        AND crt.Name LIKE '%Duplicate%'
    )
    GROUP BY PostId
)
SELECT 
    au.Id,
    au.DisplayName,
    au.Location,
    au.Reputation,
    au.TotalPosts,
    au.TotalComments,
    au.TotalVotes,
    au.PostRank,
    gbu.GoldBadges,
    gbu.LastGoldBadgeDate,
    pc.ClosureCount,
    pc.CloseReasons,
    (SELECT AVG(AnswerCount) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = au.Id 
     AND p2.PostTypeId = 1) AS AvgAnswersPerQuestion,
    ROUND(1.0 * au.TotalVotes / NULLIF(au.TotalPosts, 0), 2) AS VotesPerPost,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p3 
            WHERE p3.OwnerUserId = au.Id 
            AND p3.Tags LIKE '%<sql>%'
        ) THEN 'SQL Expert'
        WHEN au.Reputation > 100000 THEN 'Legendary'
        ELSE 'Active'
    END AS UserCategory,
    LEAD(au.DisplayName, 1) OVER (ORDER BY au.Reputation DESC) AS NextTopUser,
    PERCENT_RANK() OVER (ORDER BY au.Reputation) AS ReputationPercentile
FROM ActiveUsers au
LEFT JOIN GoldBadgeUsers gbu ON au.Id = gbu.UserId
LEFT JOIN PostClosures pc ON au.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pc.PostId)
WHERE au.Reputation > (SELECT AVG(Reputation) FROM Users WHERE CreationDate >= '2015-01-01')
UNION ALL
SELECT 
    u.Id,
    u.DisplayName,
    COALESCE(u.Location, 'Unknown'),
    u.Reputation,
    0,
    0,
    0,
    NULL,
    0,
    NULL,
    0,
    NULL,
    NULL,
    NULL,
    'Inactive',
    NULL,
    NULL
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM ActiveUsers au WHERE au.Id = u.Id)
AND u.CreationDate >= '2015-01-01'
ORDER BY Reputation DESC, PostRank NULLS LAST
LIMIT 100;
