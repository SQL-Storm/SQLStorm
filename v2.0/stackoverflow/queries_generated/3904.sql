-- {"query": "3904.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1446} 

/*  Benchmark query – heavy use of CTEs, window functions, outer joins, 
    correlated subqueries, set operators, complex expressions and NULL logic   */
WITH 
/* 1️⃣  Users enriched with badge aggregates (including users with no badges) */
UserBadgeStats AS (
    SELECT 
        u.Id                              AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COUNT(b.Id)                       AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* 2️⃣  Average score of each user’s *questions* (PostTypeId = 1) */
UserQuestionScore AS (
    SELECT 
        p.OwnerUserId                AS UserId,
        ROUND(AVG(p.Score)::numeric, 2) AS AvgQuestionScore,
        COUNT(*)                     AS QuestionCount
    FROM Posts p
    WHERE p.PostTypeId = 1               -- only questions
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/* 3️⃣  Latest post (question or answer) per user with a fancy title expression */
UserLatestPost AS (
    SELECT 
        p.OwnerUserId                AS UserId,
        p.Id                         AS LatestPostId,
        p.Title,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),

/* 4️⃣  Distinct tag count used by each user in their questions */
UserTagDiversity AS (
    SELECT 
        q.OwnerUserId                     AS UserId,
        COUNT(DISTINCT UNNEST(
            string_to_array(
                TRIM(BOTH '<>' FROM q.Tags), '><'
            )
        ))                                 AS DistinctTagCount
    FROM Posts q
    WHERE q.PostTypeId = 1               -- only questions
      AND q.Tags IS NOT NULL
    GROUP BY q.OwnerUserId
),

/* 5️⃣  Users who have voted at least once on *any* post – using a set operator */
Voters AS (
    SELECT DISTINCT v.UserId
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    UNION ALL
    SELECT DISTINCT c.UserId
    FROM Comments c
    WHERE c.UserId IS NOT NULL
),

/* 6️⃣  Final enriched user data (joins all the pieces together) */
EnrichedUsers AS (
    SELECT 
        ub.UserId,
        ub.DisplayName,
        ub.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        COALESCE(uqs.AvgQuestionScore, 0)      AS AvgQuestionScore,
        COALESCE(uqs.QuestionCount, 0)          AS QuestionCount,
        COALESCE(utd.DistinctTagCount, 0)       AS DistinctTagCount,
        /* Latest post title – fallback to '(no posts)' when none */
        COALESCE(lp.Title, '(no posts)')        AS LatestPostTitle,
        /* Boolean flag – true if user accessed the site in the last 30 days */
        CASE 
            WHEN u.LastAccessDate >= NOW() - INTERVAL '30 days' THEN TRUE
            ELSE FALSE
        END                                     AS IsRecentlyActive,
        /* Composite score for ranking – weighted sum */
        (ub.Reputation * 0.4
         + ub.TotalBadges * 10
         + COALESCE(uqs.AvgQuestionScore,0) * 5
         + COALESCE(utd.DistinctTagCount,0) * 2) AS CompositeScore
    FROM UserBadgeStats ub
    LEFT JOIN UserQuestionScore uqs ON uqs.UserId = ub.UserId
    LEFT JOIN UserTagDiversity utd   ON utd.UserId = ub.UserId
    LEFT JOIN (
        SELECT UserId, Title
        FROM UserLatestPost
        WHERE rn = 1
    ) lp ON lp.UserId = ub.UserId
    JOIN Users u ON u.Id = ub.UserId               -- to get LastAccessDate
)

/* 7️⃣  Final result set – top 100 users by composite score, together with
        a flag indicating whether they have ever voted or commented      */
SELECT
    eu.UserId,
    eu.DisplayName,
    eu.Reputation,
    eu.GoldBadges,
    eu.SilverBadges,
    eu.BronzeBadges,
    eu.TotalBadges,
    eu.AvgQuestionScore,
    eu.QuestionCount,
    eu.DistinctTagCount,
    eu.LatestPostTitle,
    eu.IsRecentlyActive,
    eu.CompositeScore,
    /* Has the user ever participated in voting or commenting? */
    CASE WHEN v.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS HasVotedOrCommented
FROM EnrichedUsers eu
LEFT JOIN Voters v ON v.UserId = eu.UserId
WHERE eu.Reputation > 1000                     -- filter out very low‑rep accounts
ORDER BY eu.CompositeScore DESC
LIMIT 100;
