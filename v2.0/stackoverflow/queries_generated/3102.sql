-- {"query": "3102.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1390} 

/*  Performance‑benchmarking query combining CTEs, window functions, outer joins,
    correlated subqueries, set operators, string handling and NULL logic   */
WITH
/* ----------------------------------------------------------------------
   1. Aggregate badge counts per user, separating classes (Gold/Silver/Bronze)
   ---------------------------------------------------------------------- */
BadgeAgg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount,
        COUNT(*)                                        AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),

/* ----------------------------------------------------------------------
   2. Compute per‑user post statistics (questions only) with window ranks
   ---------------------------------------------------------------------- */
PostStats AS (
    SELECT
        p.OwnerUserId                     AS UserId,
        COUNT(*)                          AS QuestionCount,
        AVG(p.Score)                      AS AvgScore,
        MAX(p.CreationDate)               AS LastQuestionDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS TopScoreRank,
        STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags, '><'))), ', ') 
                                          AS AllTags
    FROM Posts p
    WHERE p.PostTypeId = 1                -- only questions
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/* ----------------------------------------------------------------------
   3. Latest activity per user (last vote, comment, or post edit)
   ---------------------------------------------------------------------- */
LatestActivity AS (
    SELECT u.Id AS UserId,
           GREATEST(
               COALESCE((SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = u.Id), '1970-01-01'),
               COALESCE((SELECT MAX(c.CreationDate) FROM Comments c WHERE c.UserId = u.Id), '1970-01-01'),
               COALESCE(u.LastAccessDate, '1970-01-01')
           ) AS LastActivity
    FROM Users u
),

/* ----------------------------------------------------------------------
   4. Users with at least one gold badge and recent activity (last 180 days)
   ---------------------------------------------------------------------- */
ActiveGoldUsers AS (
    SELECT ba.UserId
    FROM BadgeAgg ba
    JOIN LatestActivity la ON la.UserId = ba.UserId
    WHERE ba.GoldCount > 0
      AND la.LastActivity >= CURRENT_DATE - INTERVAL '180 days'
),

/* ----------------------------------------------------------------------
   5. Union of users who either have high reputation or many bronze badges
   ---------------------------------------------------------------------- */
HighRepOrBronze AS (
    SELECT u.Id AS UserId
    FROM Users u
    WHERE u.Reputation >= 20000
    UNION
    SELECT ba.UserId
    FROM BadgeAgg ba
    WHERE ba.BronzeCount >= 100
),

/* ----------------------------------------------------------------------
   6. Final list: users satisfying all criteria, enriched with stats
   ---------------------------------------------------------------------- */
FinalUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ps.QuestionCount, 0)          AS QuestionCount,
        COALESCE(ps.AvgScore, 0)               AS AvgQuestionScore,
        COALESCE(ba.GoldCount, 0)              AS GoldBadges,
        COALESCE(ba.SilverCount, 0)            AS SilverBadges,
        COALESCE(ba.BronzeCount, 0)            AS BronzeBadges,
        COALESCE(ps.AllTags, '')               AS TagsUsed,
        la.LastActivity
    FROM Users u
    LEFT JOIN BadgeAgg ba     ON ba.UserId = u.Id
    LEFT JOIN PostStats ps    ON ps.UserId = u.Id
    LEFT JOIN LatestActivity la ON la.UserId = u.Id
    WHERE u.Id IN (SELECT UserId FROM ActiveGoldUsers)
      AND u.Id IN (SELECT UserId FROM HighRepOrBronze)
      AND (u.Location IS NOT NULL AND u.Location <> '')
      AND (u.WebsiteUrl IS NOT NULL OR u.AboutMe IS NOT NULL)
)

SELECT
    fu.Id,
    fu.DisplayName,
    fu.Reputation,
    fu.QuestionCount,
    ROUND(fu.AvgQuestionScore, 2)          AS AvgScoreRounded,
    fu.GoldBadges,
    fu.SilverBadges,
    fu.BronzeBadges,
    fu.TagsUsed,
    fu.LastActivity,
    CASE
        WHEN fu.Reputation >= 50000 THEN 'Legendary'
        WHEN fu.Reputation >= 20000 THEN 'PowerUser'
        WHEN fu.Reputation >= 10000 THEN 'Experienced'
        ELSE 'Contributor'
    END                                    AS ReputationTier,
    /* Demonstrate NULL logic with COALESCE and CASE */
    COALESCE(NULLIF(fu.TagsUsed, ''), 'No tags recorded') AS TagSummary,
    /* Demonstrate a correlated subquery counting recent up‑votes */
    (SELECT COUNT(*)
       FROM Votes v
      WHERE v.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = fu.Id)
        AND v.VoteTypeId = 2                 -- UpMod
        AND v.CreationDate >= CURRENT_DATE - INTERVAL '30 days') AS RecentUpVotes
FROM FinalUsers fu
ORDER BY fu.Reputation DESC, fu.GoldBadges DESC, fu.Id
LIMIT 100;
