-- {"query": "3494.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2352} 

/*  Complex benchmark query using the StackOverflow schema  */
WITH
/* ------------------------------------------------------------------
   1.  Aggregate per‑user statistics (badges, posts, votes, etc.)
   ------------------------------------------------------------------ */
UserStats AS (
    SELECT
        u.Id                                            AS UserId,
        u.DisplayName,
        u.Reputation,
        /* badge counts by class */
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        /* post counts per type */
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        /* net vote balance (up‑votes – down‑votes) issued by the user */
        COALESCE((
            SELECT SUM(CASE vt.VoteTypeId
                         WHEN 2 THEN  1   /* UpMod   */
                         WHEN 3 THEN -1   /* DownMod */
                         ELSE 0
                       END)
            FROM Votes vt
            WHERE vt.UserId = u.Id
        ),0)                                            AS VoteBalance
    FROM Users u
),

/* ------------------------------------------------------------------
   2.  Most recent activity dates (posts, votes, comments) per user
   ------------------------------------------------------------------ */
RecentActivity AS (
    SELECT
        p.OwnerUserId                                      AS UserId,
        MAX(p.CreationDate)                               AS LastPostDate,
        MAX(v.CreationDate)                               AS LastVoteDate,
        MAX(c.CreationDate)                               AS LastCommentDate
    FROM Posts p
    LEFT JOIN Votes   v ON v.PostId = p.Id AND v.UserId = p.OwnerUserId
    LEFT JOIN Comments c ON c.PostId = p.Id AND c.UserId = p.OwnerUserId
    GROUP BY p.OwnerUserId
),

/* ------------------------------------------------------------------
   3.  Top tag (by usage count) for each user’s questions
   ------------------------------------------------------------------ */
UserTopTag AS (
    SELECT
        q.OwnerUserId                                     AS UserId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId
                           ORDER BY COUNT(*) DESC)      AS rn
    FROM Posts q
    /* split the <tag> list; PostgreSQL syntax – adapt for other DBs */
    CROSS JOIN LATERAL regexp_split_to_table(
        TRIM(BOTH '<>' FROM q.Tags), '[><]+') AS tag_name
    JOIN Tags t ON t.TagName = tag_name
    WHERE q.PostTypeId = 1      -- only questions
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
    COALESCE(ra.LastPostDate,      TIMESTAMP '1970-01-01') AS LastPostDate,
    COALESCE(ra.LastVoteDate,      TIMESTAMP '1970-01-01') AS LastVoteDate,
    COALESCE(ra.LastCommentDate,   TIMESTAMP '1970-01-01') AS LastCommentDate,
    /* weighted activity score – used for ranking */
    ROW_NUMBER() OVER (
        ORDER BY ( us.Reputation * 0.4
                 + us.GoldBadges   * 100
                 + us.SilverBadges * 50
                 + us.BronzeBadges * 20
                 + us.QuestionCount* 2
                 + us.AnswerCount  * 5
                 + us.VoteBalance ) DESC
    )                                            AS ActivityRank,
    /* pick the top tag (rn = 1) – may be NULL if the user never posted a tagged question */
    tt.TagName                                    AS TopTag
FROM UserStats us
LEFT JOIN RecentActivity ra   ON ra.UserId   = us.UserId
LEFT JOIN UserTopTag tt       ON tt.UserId   = us.UserId AND tt.rn = 1
WHERE us.Reputation > 1000                -- filter for “active” users
  AND (us.GoldBadges+us.SilverBadges+us.BronzeBadges) > 0
  AND (us.QuestionCount+us.AnswerCount) > 5
/* ------------------------------------------------------------------
   4.  Add a synthetic “Community” row via UNION ALL
   ------------------------------------------------------------------ */
UNION ALL
SELECT
    -1                                            AS UserId,
    'Community'                                   AS DisplayName,
    NULL                                          AS Reputation,
    0                                             AS GoldBadges,
    0                                             AS SilverBadges,
    0                                             AS BronzeBadges,
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
    ),0)                                          AS VoteBalance,
    NULL                                          AS LastPostDate,
    NULL                                          AS LastVoteDate,
    NULL                                          AS LastCommentDate,
    NULL                                          AS ActivityRank,
    NULL                                          AS TopTag
/* ------------------------------------------------------------------
   5.  Order the final result set and limit for benchmarking
   ------------------------------------------------------------------ */
ORDER BY ActivityRank
LIMIT 100;
