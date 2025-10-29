WITH UserPostStats AS (
    SELECT
        u.Id                                            AS UserId,
        COALESCE(u.DisplayName, 'Anonymous')            AS DisplayName,
        u.Reputation,
        COUNT(p.Id)                                     AS PostCount,
        SUM(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS TotalScore,
        AVG(p.Score)                                    AS AvgScore,
        MAX(p.CreationDate)                             AS LastPostDate,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END)    AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END)    AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Votes v
        ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TopUsers AS (
    SELECT *
    FROM UserPostStats
    WHERE Reputation > 10000
      AND PostCount >= 5
      AND TotalScore / NULLIF(PostCount, 0) > 10
    ORDER BY Reputation DESC
    FETCH FIRST 10 ROWS ONLY
),

UserBadges AS (
    SELECT
        b.UserId,
        STRING_AGG(b.Name, ', ' ORDER BY b.Class) AS BadgeList,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges b
    GROUP BY b.UserId
),

RecentEdits AS (
    SELECT
        ph.UserId,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.UserId
),

TagStats AS (
    SELECT
        p.OwnerUserId                                 AS UserId,
        COUNT(CASE WHEN LOWER(p.Tags) LIKE '%<javascript>%' THEN 1 END) AS JavaScriptTagCount,
        COUNT(CASE WHEN LOWER(p.Tags) LIKE '%<sql>%' THEN 1 END)        AS SqlTagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
)

SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.TotalScore,
    tu.AvgScore,
    tu.LastPostDate,
    ub.BadgeList,
    ub.GoldCount,
    ub.SilverCount,
    ub.BronzeCount,
    re.LastEditDate,
    re.EditCount,
    ts.JavaScriptTagCount,
    ts.SqlTagCount,
    CASE
        WHEN COALESCE(ts.JavaScriptTagCount,0) > 0 AND COALESCE(ts.SqlTagCount,0) > 0 THEN 'FullStack'
        WHEN COALESCE(ts.JavaScriptTagCount,0) > 0 THEN 'JS Specialist'
        WHEN COALESCE(ts.SqlTagCount,0) > 0 THEN 'SQL Specialist'
        ELSE 'Generalist'
    END AS ExpertiseCategory,
    ('Reputation: ' || tu.Reputation || ', Posts: ' || tu.PostCount) AS Summary
FROM TopUsers tu
LEFT JOIN UserBadges ub    ON ub.UserId = tu.UserId
LEFT JOIN RecentEdits re   ON re.UserId = tu.UserId
LEFT JOIN TagStats ts      ON ts.UserId = tu.UserId
WHERE (COALESCE(ub.GoldCount,0) > 0 OR COALESCE(ub.SilverCount,0) > 2)
  AND (re.EditCount IS NULL OR re.EditCount > 5)

UNION ALL

SELECT
    u.Id,
    COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
    u.Reputation,
    0                                   AS PostCount,
    0                                   AS TotalScore,
    NULL                                AS AvgScore,
    NULL                                AS LastPostDate,
    NULL                                AS BadgeList,
    0                                   AS GoldCount,
    0                                   AS SilverCount,
    0                                   AS BronzeCount,
    NULL                                AS LastEditDate,
    0                                   AS EditCount,
    0                                   AS JavaScriptTagCount,
    0                                   AS SqlTagCount,
    'NoPosts'                           AS ExpertiseCategory,
    ('Reputation: ' || u.Reputation)    AS Summary
FROM Users u
WHERE NOT EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1
    )
  AND u.Reputation > 15000

ORDER BY Reputation DESC, PostCount DESC
LIMIT 20;