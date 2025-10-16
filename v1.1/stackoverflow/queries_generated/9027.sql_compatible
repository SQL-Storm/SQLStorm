WITH
CTE_UserBadges AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges b
    GROUP BY b.UserId
),
CTE_CorrelatedVotes AS (
    SELECT
        u.Id AS UserId,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesCast,
        (SELECT COUNT(*) 
         FROM Votes v 
         JOIN Posts p ON p.Id = v.PostId 
         WHERE p.OwnerUserId = u.Id AND v.VoteTypeId = 2
        ) AS UpVotesReceived
    FROM Users u
),
CTE_TopPosters AS (
    SELECT
        u.Id AS UserId,
        AVG(CAST(p.Score AS DOUBLE PRECISION))       AS AvgQScore,
        COUNT(c.Id)                                   AS CommentCount
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Comments c ON c.UserId      = u.Id
    GROUP BY u.Id
    HAVING AVG(CAST(p.Score AS DOUBLE PRECISION)) > 5
       AND COUNT(c.Id) > 20
)
SELECT
    u.DisplayName,
    RIGHT(u.DisplayName,10)                                  AS NameSnippet,
    COALESCE(ub.GoldCount,0)                                 AS GoldCount,
    COALESCE(ub.SilverCount,0)                               AS SilverCount,
    COALESCE(ub.BronzeCount,0)                               AS BronzeCount,
    CAST(tp.AvgQScore AS DECIMAL(10,2))                      AS AvgQScore,
    tp.CommentCount,
    cv.UpVotesCast,
    cv.UpVotesReceived,
    CASE WHEN cv.UpVotesReceived > cv.UpVotesCast THEN 'Popular' ELSE 'Active' END AS UserStatus,
    CASE WHEN u.Reputation > 10000 THEN 'Veteran' ELSE 'Newbie' END AS UserType
FROM CTE_TopPosters tp
JOIN Users u               ON u.Id      = tp.UserId
LEFT JOIN CTE_UserBadges ub ON ub.UserId = u.Id
LEFT JOIN CTE_CorrelatedVotes cv ON cv.UserId = u.Id
WHERE EXISTS (
    SELECT 1
    FROM Posts p2
    WHERE p2.OwnerUserId = u.Id
      AND p2.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month')
)

UNION

SELECT
    u.DisplayName,
    RIGHT(u.DisplayName,10),
    COALESCE(ub.GoldCount,0),
    COALESCE(ub.SilverCount,0),
    COALESCE(ub.BronzeCount,0),
    CAST(0.00 AS DECIMAL(10,2)),
    0,
    0,
    0,
    'Legacy',
    'Veteran'
FROM Users u
LEFT JOIN CTE_UserBadges ub ON ub.UserId = u.Id
WHERE u.Reputation > 100000

INTERSECT

SELECT
    u.DisplayName,
    RIGHT(u.DisplayName,10),
    COALESCE(ub.GoldCount,0),
    COALESCE(ub.SilverCount,0),
    COALESCE(ub.BronzeCount,0),
    CAST(AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY u.Id) AS DECIMAL(10,2)),
    COUNT(c.Id) OVER (PARTITION BY u.Id),
    cv.UpVotesCast,
    cv.UpVotesReceived,
    'Elite',
    'Champion'
FROM Users u
LEFT JOIN CTE_UserBadges ub ON ub.UserId = u.Id
LEFT JOIN Posts    p  ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.UserId      = u.Id
JOIN CTE_CorrelatedVotes cv ON cv.UserId = u.Id
WHERE u.CreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years')

EXCEPT

SELECT
    u.DisplayName,
    RIGHT(u.DisplayName,10),
    0,
    0,
    0,
    CAST(0.00 AS DECIMAL(10,2)),
    0,
    0,
    0,
    'Inactive',
    'Retired'
FROM Users u
WHERE u.LastAccessDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years')

ORDER BY UpVotesReceived DESC, AvgQScore DESC;