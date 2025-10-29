-- {"query": "3958.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2158} 

WITH UserPostStats AS (
    SELECT 
        u.Id                         AS UserId,
        u.DisplayName                AS DisplayName,
        u.Reputation                 AS Reputation,
        COUNT(p.Id)                  AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score)                 AS AvgScore,
        MAX(p.CreationDate)          AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

UserBadgeAgg AS (
    SELECT 
        b.UserId,
        STRING_AGG(b.Name, ', ')                     AS BadgeList,
        COUNT(*) FILTER (WHERE b.Class = 1)           AS GoldCount,
        COUNT(*) FILTER (WHERE b.Class = 2)           AS SilverCount,
        COUNT(*) FILTER (WHERE b.Class = 3)           AS BronzeCount
    FROM Badges b
    GROUP BY b.UserId
),

UserRecentActivity AS (
    SELECT 
        u.Id                                 AS UserId,
        MAX(v.CreationDate)                  AS LastVoteDate,
        MAX(c.CreationDate)                  AS LastCommentDate,
        MAX(ph.CreationDate)                 AS LastHistoryDate
    FROM Users u
    LEFT JOIN Votes v      ON v.UserId = u.Id
    LEFT JOIN Comments c   ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id
),

TopScoringPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.OwnerUserId,
        p.CreationDate,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.Score DESC, p.CreationDate DESC
        ) AS rn
    FROM Posts p
    WHERE p.Score IS NOT NULL
),

UserTopPost AS (
    SELECT 
        tsp.OwnerUserId                AS UserId,
        tsp.Title,
        tsp.Score,
        tsp.CreationDate
    FROM TopScoringPosts tsp
    JOIN (
        SELECT OwnerUserId, MIN(rn) AS min_rn
        FROM TopScoringPosts
        GROUP BY OwnerUserId
    ) m ON tsp.OwnerUserId = m.OwnerUserId AND tsp.rn = m.min_rn
)

SELECT
    ups.UserId,
    COALESCE(ups.DisplayName, 'Anonymous') || ' (' || COALESCE(ups.Reputation::text,'0') || ')' AS UserInfo,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ROUND(COALESCE(ups.AvgScore,0)::numeric,2)               AS AvgScore,
    ub.BadgeList,
    ub.GoldCount,
    ub.SilverCount,
    ub.BronzeCount,
    ura.LastVoteDate,
    ura.LastCommentDate,
    ura.LastHistoryDate,
    utp.Title       AS TopPostTitle,
    utp.Score       AS TopPostScore,
    utp.CreationDate AS TopPostDate
FROM UserPostStats ups
LEFT JOIN UserBadgeAgg ub          ON ub.UserId = ups.UserId
LEFT JOIN UserRecentActivity ura  ON ura.UserId = ups.UserId
LEFT JOIN UserTopPost utp         ON utp.UserId = ups.UserId
WHERE ups.TotalPosts > 0 OR ub.UserId IS NOT NULL

UNION ALL

SELECT
    u.Id,
    COALESCE(u.DisplayName, 'Anonymous') || ' (' || COALESCE(u.Reputation::text,'0') || ')' AS UserInfo,
    0                  AS TotalPosts,
    0                  AS Questions,
    0                  AS Answers,
    NULL               AS AvgScore,
    NULL               AS BadgeList,
    0                  AS GoldCount,
    0                  AS SilverCount,
    0                  AS BronzeCount,
    NULL               AS LastVoteDate,
    NULL               AS LastCommentDate,
    NULL               AS LastHistoryDate,
    NULL               AS TopPostTitle,
    NULL               AS TopPostScore,
    NULL               AS TopPostDate
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY AvgScore DESC NULLS LAST, GoldCount DESC, Reputation DESC
LIMIT 100;
