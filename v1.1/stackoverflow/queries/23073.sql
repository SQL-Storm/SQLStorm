-- {"query": "23073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 978} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT AVG(CAST(p.Score AS FLOAT)) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)) AS AvgPostScore
    FROM Users u
    WHERE u.Reputation > 1000
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(CASE WHEN b.Class = 1 THEN 1 END) >= 1
),
PostActivity AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPosts,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts p
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, t.TagName
),
VoteSubquery AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes
    FROM Votes v
    GROUP BY v.PostId
),
CombinedStats AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.DisplayName,
        us.UserLocation,
        us.RepRank,
        us.QuestionCount,
        us.AvgPostScore,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.BadgeNames, 'No Badges') AS BadgeNames,
        pa.TotalPosts,
        pa.LastPostDate,
        pa.ClosedPosts,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.UserId = us.UserId) AS CommentCount,
        (SELECT MAX(vs.NetVotes) FROM Posts p INNER JOIN VoteSubquery vs ON p.Id = vs.PostId WHERE p.OwnerUserId = us.UserId) AS MaxNetVotes
    FROM UserStats us
    LEFT OUTER JOIN BadgeStats bs ON us.UserId = bs.UserId
    LEFT OUTER JOIN PostActivity pa ON us.UserId = pa.OwnerUserId AND pa.TagRank = 1
    WHERE us.RepRank <= 50
    UNION
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        NULL AS RepRank,
        0 AS QuestionCount,
        NULL AS AvgPostScore,
        0 AS GoldBadges,
        'Inactive' AS BadgeNames,
        0 AS TotalPosts,
        NULL AS LastPostDate,
        0 AS ClosedPosts,
        0 AS CommentCount,
        NULL AS MaxNetVotes
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
    AND u.Reputation BETWEEN 1 AND 100
    ORDER BY Reputation DESC
    LIMIT 10
)
SELECT 
    UserId,
    DisplayName,
    UserLocation,
    Reputation,
    RepRank,
    QuestionCount,
    AvgPostScore,
    GoldBadges,
    BadgeNames,
    TotalPosts,
    LastPostDate,
    ClosedPosts,
    CommentCount,
    MaxNetVotes,
    CASE 
        WHEN AvgPostScore > 10 AND GoldBadges > 0 THEN 'High Performer' 
        WHEN ClosedPosts > TotalPosts * 0.5 THEN 'Needs Improvement' 
        ELSE 'Standard' 
    END AS PerformanceCategory,
    COALESCE(CAST((QuestionCount + TotalPosts) / NULLIF(CommentCount, 0) AS FLOAT), 0) AS ActivityRatio
FROM CombinedStats
WHERE (RepRank IS NULL OR RepRank <= 20) AND (LastPostDate > '2020-01-01' OR LastPostDate IS NULL)
ORDER BY Reputation DESC, ActivityRatio DESC;