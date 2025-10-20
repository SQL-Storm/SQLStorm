-- {"query": "25029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2077} 

WITH 
    UserStats AS (
        SELECT 
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(u.Views, 0) AS Views,
            u.UpVotes,
            u.DownVotes,
            COUNT(DISTINCT b.Id) AS BadgeCount
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
    ),
    RecentPosts AS (
        SELECT 
            p.OwnerUserId AS UserId,
            COUNT(*) FILTER (WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days') AS RecentPostCount,
            MAX(p.CreationDate) AS LastPostDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    TagUsage AS (
        SELECT 
            p.OwnerUserId AS UserId,
            UNNEST(
                STRING_TO_ARRAY(
                    REGEXP_REPLACE(p.Tags, '^<|>$', '', 'g'),
                    '><'
                )
            ) AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ),
    TopTags AS (
        SELECT 
            UserId,
            Tag,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY cnt DESC) AS rn
        FROM (
            SELECT 
                UserId,
                Tag,
                COUNT(*) AS cnt
            FROM TagUsage
            GROUP BY UserId, Tag
        ) t
    ),
    VoteAgg AS (
        SELECT 
            v.PostId,
            SUM(CASE 
                    WHEN v.VoteTypeId = 2 THEN 1    -- UpMod
                    WHEN v.VoteTypeId = 3 THEN -1   -- DownMod
                    ELSE 0
                END) AS NetScore
        FROM Votes v
        GROUP BY v.PostId
    ),
    PostScoreStats AS (
        SELECT 
            p.OwnerUserId AS UserId,
            AVG(COALESCE(va.NetScore, 0)) AS AvgPostScore,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(va.NetScore, 0))
                OVER (PARTITION BY p.OwnerUserId) AS MedianPostScore
        FROM Posts p
        LEFT JOIN VoteAgg va ON va.PostId = p.Id
        WHERE p.PostTypeId IN (1, 2)   -- Questions and Answers
        GROUP BY p.OwnerUserId
    ),
    Combined AS (
        SELECT 
            us.Id,
            us.DisplayName,
            us.Reputation,
            us.Views,
            us.UpVotes,
            us.DownVotes,
            us.BadgeCount,
            rp.RecentPostCount,
            rp.LastPostDate,
            ps.AvgPostScore,
            ps.MedianPostScore
        FROM UserStats us
        LEFT JOIN RecentPosts rp ON rp.UserId = us.Id
        LEFT JOIN PostScoreStats ps ON ps.UserId = us.Id
    )
SELECT 
    c.Id,
    c.DisplayName,
    c.Reputation,
    c.Views,
    c.UpVotes,
    c.DownVotes,
    c.BadgeCount,
    COALESCE(c.RecentPostCount, 0) AS RecentPostCount,
    c.LastPostDate,
    ROUND(c.AvgPostScore, 2) AS AvgPostScore,
    c.MedianPostScore,
    STRING_AGG(tt.Tag, ', ') FILTER (WHERE tt.rn <= 3) AS Top3Tags
FROM Combined c
LEFT JOIN TopTags tt ON tt.UserId = c.Id
WHERE 
    c.Reputation > 1000
    AND (c.BadgeCount IS NULL OR c.BadgeCount > 5)
GROUP BY 
    c.Id, c.DisplayName, c.Reputation, c.Views, c.UpVotes, c.DownVotes,
    c.BadgeCount, c.RecentPostCount, c.LastPostDate, c.AvgPostScore, c.MedianPostScore
HAVING COUNT(*) > 0
ORDER BY c.Reputation DESC
LIMIT 100

UNION ALL

SELECT 
    NULL AS Id,
    'SUMMARY' AS DisplayName,
    SUM(c.Reputation) AS Reputation,
    SUM(c.Views) AS Views,
    SUM(c.UpVotes) AS UpVotes,
    SUM(c.DownVotes) AS DownVotes,
    SUM(c.BadgeCount) AS BadgeCount,
    SUM(c.RecentPostCount) AS RecentPostCount,
    MAX(c.LastPostDate) AS LastPostDate,
    ROUND(AVG(c.AvgPostScore), 2) AS AvgPostScore,
    NULL AS MedianPostScore,
    NULL AS Top3Tags
FROM Combined c;
