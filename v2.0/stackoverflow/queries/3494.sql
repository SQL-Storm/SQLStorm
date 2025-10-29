WITH
UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        COALESCE((
            SELECT SUM(CASE vt.VoteTypeId
                         WHEN 2 THEN  1
                         WHEN 3 THEN -1
                         ELSE 0
                       END)
            FROM Votes vt
            WHERE vt.UserId = u.Id
        ),0) AS VoteBalance
    FROM Users u
),

RecentActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(v.CreationDate) AS LastVoteDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = p.OwnerUserId
    LEFT JOIN Comments c ON c.PostId = p.Id AND c.UserId = p.OwnerUserId
    GROUP BY p.OwnerUserId
),

UserTopTag AS (
    SELECT
        q.OwnerUserId AS UserId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM Posts q
    CROSS JOIN LATERAL (
        -- generic split: replace regexp_split_to_table for DBs that support standard functions.
        -- For engines without regexp_split_to_table, this needs to be adapted; keep as-is for Postgres-compatible.
        SELECT regexp_split_to_table(TRIM(BOTH '<>' FROM q.Tags), '[><]+') AS tag_name
    ) tag_split
    JOIN Tags t ON t.TagName = tag_split.tag_name
    WHERE q.PostTypeId = 1
      AND q.Tags IS NOT NULL
    GROUP BY q.OwnerUserId, t.TagName
)

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    us.VoteBalance,
    COALESCE(ra.LastPostDate, TIMESTAMP '1970-01-01') AS LastPostDate,
    COALESCE(ra.LastVoteDate, TIMESTAMP '1970-01-01') AS LastVoteDate,
    COALESCE(ra.LastCommentDate, TIMESTAMP '1970-01-01') AS LastCommentDate,
    ROW_NUMBER() OVER (
        ORDER BY ( us.Reputation * 0.4
                 + us.GoldBadges   * 100
                 + us.SilverBadges * 50
                 + us.BronzeBadges * 20
                 + us.QuestionCount* 2
                 + us.AnswerCount  * 5
                 + us.VoteBalance ) DESC
    ) AS ActivityRank,
    tt.TagName AS TopTag
FROM UserStats us
LEFT JOIN RecentActivity ra ON ra.UserId = us.UserId
LEFT JOIN UserTopTag tt ON tt.UserId = us.UserId AND tt.rn = 1
WHERE us.Reputation > 1000
  AND (us.GoldBadges + us.SilverBadges + us.BronzeBadges) > 0
  AND (us.QuestionCount + us.AnswerCount) > 5

UNION ALL

SELECT
    -1 AS UserId,
    'Community' AS DisplayName,
    NULL AS Reputation,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = -1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = -1) AS AnswerCount,
    COALESCE((
        SELECT SUM(CASE vt.VoteTypeId
                     WHEN 2 THEN  1
                     WHEN 3 THEN -1
                     ELSE 0
                   END)
        FROM Votes vt
        WHERE vt.UserId IS NULL
    ),0) AS VoteBalance,
    NULL AS LastPostDate,
    NULL AS LastVoteDate,
    NULL AS LastCommentDate,
    NULL AS ActivityRank,
    NULL AS TopTag

ORDER BY ActivityRank
LIMIT 100;