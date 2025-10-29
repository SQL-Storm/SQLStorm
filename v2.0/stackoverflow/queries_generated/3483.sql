-- {"query": "3483.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3197} 

/*  Comprehensive performance‑benchmark query for the StackOverflow schema  */
WITH
/* -------------------------------------------------------------
   1.  Basic per‑user aggregates (posts, questions, answers, badges)
   ------------------------------------------------------------- */
UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           COALESCE( (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id), 0)                AS TotalPosts,
           COALESCE( (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1), 0) AS QuestionCount,
           COALESCE( (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2), 0) AS AnswerCount,
           COALESCE( (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id), 0)                  AS BadgeCount
    FROM Users u
),

/* -------------------------------------------------------------
   2.  Badge class breakdown per user
   ------------------------------------------------------------- */
BadgeAgg AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),

/* -------------------------------------------------------------
   3.  Top‑scoring post per user (question or answer)
   ------------------------------------------------------------- */
TopPostPerUser AS (
    SELECT p.OwnerUserId                              AS UserId,
           p.Id                                        AS PostId,
           p.Score,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                              ORDER BY p.Score DESC NULLS LAST,
                                       p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)               /* only Q&A */
),

UserTopPost AS (
    SELECT UserId, PostId, Score
    FROM TopPostPerUser
    WHERE rn = 1
),

/* -------------------------------------------------------------
   4.  Normalise the tag list stored as a raw string
   ------------------------------------------------------------- */
TagExtract AS (
    SELECT p.Id                                         AS PostId,
           regexp_split_to_table(p.Tags, '[><]')        AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),

/* -------------------------------------------------------------
   5.  Statistics per tag (post count, avg score, last used)
   ------------------------------------------------------------- */
TagStats AS (
    SELECT te.TagName,
           COUNT(*)                                               AS TagPostCount,
           AVG(p.Score)::numeric(10,2)                            AS AvgTagScore,
           MAX(p.CreationDate)                                    AS LastTagUse
    FROM TagExtract te
    JOIN Posts p ON p.Id = te.PostId
    GROUP BY te.TagName
),

/* -------------------------------------------------------------
   6.  Tag activity per user (distinct tags, concatenated list)
   ------------------------------------------------------------- */
UserTagActivity AS (
    SELECT u.Id                                            AS UserId,
           COUNT(DISTINCT te.TagName)                      AS DistinctTagCount,
           STRING_AGG(DISTINCT te.TagName, ', ')
               FILTER (WHERE te.TagName IS NOT NULL)      AS TopTags
    FROM Users u
    LEFT JOIN Posts p      ON p.OwnerUserId = u.Id
    LEFT JOIN TagExtract te ON te.PostId = p.Id
    GROUP BY u.Id
),

/* -------------------------------------------------------------
   7.  Rank users by reputation, then badge count
   ------------------------------------------------------------- */
RankedUsers AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.TotalPosts,
           us.QuestionCount,
           us.AnswerCount,
           us.BadgeCount,
           ba.GoldBadges,
           ba.SilverBadges,
           ba.BronzeBadges,
           up.PostId                                   AS TopPostId,
           up.Score                                    AS TopPostScore,
           uta.DistinctTagCount,
           uta.TopTags,
           ROW_NUMBER() OVER (ORDER BY us.Reputation DESC,
                                          us.BadgeCount DESC) AS Rank
    FROM UserStats us
    LEFT JOIN BadgeAgg        ba  ON ba.UserId = us.Id
    LEFT JOIN UserTopPost     up  ON up.UserId = us.Id
    LEFT JOIN UserTagActivity uta ON uta.UserId = us.Id
)

-- ============================================================
-- Final result set: top 100 users + a synthetic row for users
-- with no activity (demonstrating UNION ALL and NULL handling)
-- ============================================================
SELECT r.Id,
       r.DisplayName,
       r.Reputation,
       r.TotalPosts,
       r.QuestionCount,
       r.AnswerCount,
       r.BadgeCount,
       COALESCE(r.GoldBadges,   0) AS GoldBadges,
       COALESCE(r.SilverBadges, 0) AS SilverBadges,
       COALESCE(r.BronzeBadges, 0) AS BronzeBadges,
       r.TopPostId,
       r.TopPostScore,
       r.DistinctTagCount,
       r.TopTags,
       r.Rank,
       CASE
           WHEN r.Reputation > 20000 THEN 'Elite'
           WHEN r.Reputation > 10000 THEN 'Pro'
           WHEN r.Reputation > 5000  THEN 'Adept'
           ELSE 'Learner'
       END AS ReputationTier,
       (SELECT COUNT(*) FROM Users u2 WHERE u2.Reputation > r.Reputation) + 1 AS HigherReputationCount
FROM RankedUsers r
WHERE r.Rank <= 100

UNION ALL

/* -------------------------------------------------------------
   Synthetic row for "no‑activity" users (illustrates EXISTS/NOT EXISTS)
   ------------------------------------------------------------- */
SELECT NULL::int          AS Id,
       'No Activity Users' AS DisplayName,
       NULL::int          AS Reputation,
       0                  AS TotalPosts,
       0                  AS QuestionCount,
       0                  AS AnswerCount,
       0                  AS BadgeCount,
       0                  AS GoldBadges,
       0                  AS SilverBadges,
       0                  AS BronzeBadges,
       NULL::int          AS TopPostId,
       NULL::int          AS TopPostScore,
       0                  AS DistinctTagCount,
       NULL::text         AS TopTags,
       NULL::int          AS Rank,
       'None'             AS ReputationTier,
       (SELECT COUNT(*) FROM Users) AS HigherReputationCount
WHERE EXISTS (
    SELECT 1
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
);
