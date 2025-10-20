WITH UserQuartiles AS (
    SELECT
        Id,
        Reputation,
        NTILE(4) OVER (ORDER BY Reputation DESC) AS RepQuartile,
        COALESCE(DisplayName, 'N/A') AS DisplayName
    FROM Users
),
TopPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserTopPosts AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.RepQuartile,
        t.PostId,
        t.Score,
        t.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY t.Score DESC, t.CreationDate DESC) AS rn
    FROM UserQuartiles u
    JOIN TopPosts t
        ON t.OwnerUserId = u.Id
)
SELECT
    utp.UserId,
    utp.Reputation,
    utp.RepQuartile,
    COUNT(utp.PostId) FILTER (WHERE utp.rn <= 3) AS Top3PostCount,
    AVG(CASE WHEN utp.rn <= 3 THEN utp.Score END) AS AvgTop3Score,
    MAX(CASE WHEN utp.rn <= 3 THEN utp.Score END) AS MaxTop3Score
FROM UserTopPosts utp
GROUP BY
    utp.UserId,
    utp.Reputation,
    utp.RepQuartile;