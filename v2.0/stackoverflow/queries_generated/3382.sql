-- {"query": "3382.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1952} 

/*  Benchmark query – combines CTEs, window functions, outer joins, 
    correlated subqueries, set operators, string handling and NULL logic */
WITH
/* ------------------------------------------------------------------
   1️⃣  Per‑user aggregate stats for questions and answers
   ------------------------------------------------------------------ */
UserAggregates AS (
    SELECT
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation                           AS TotalReputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END)
                                                AS QuestionsWithAccepted,
        MAX(p.CreationDate)                   AS FirstPostDate,
        /* Correlated sub‑query: latest post date per user */
        (SELECT MAX(p2.CreationDate)
         FROM Posts p2
         WHERE p2.OwnerUserId = u.Id)        AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p
          ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* ------------------------------------------------------------------
   2️⃣  Badge breakdown (gold/silver/bronze) per user
   ------------------------------------------------------------------ */
UserBadges AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount,
        COUNT(*)                                      AS TotalBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),

/* ------------------------------------------------------------------
   3️⃣  Tag usage: count distinct tags a user has ever posted in
   ------------------------------------------------------------------ */
UserTagUsage AS (
    SELECT
        p.OwnerUserId                                      AS UserId,
        COUNT(DISTINCT UNNEST(string_to_array(
                 REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), 
                 ' ')))                                    AS DistinctTagCount
    FROM Posts p
    WHERE p.PostTypeId = 1          -- only questions have Tags
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
),

/* ------------------------------------------------------------------
   4️⃣  Recent activity snapshot (last 30 days)
   ------------------------------------------------------------------ */
RecentActivity AS (
    SELECT
        ua.UserId,
        COALESCE(ua.QuestionCount,0)            AS RecentQuestions,
        COALESCE(ua.AnswerCount,0)              AS RecentAnswers,
        SUM(v.VoteTypeId = 2)                   AS RecentUpvotes,
        SUM(v.VoteTypeId = 3)                   AS RecentDownvotes
    FROM (
        SELECT
            p.OwnerUserId                               AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)    AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)    AS AnswerCount
        FROM Posts p
        WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY p.OwnerUserId
    ) ua
    LEFT JOIN Votes v
           ON v.PostId = ua.UserId
          AND v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY ua.UserId, ua.QuestionCount, ua.AnswerCount
),

/* ------------------------------------------------------------------
   5️⃣  Union of two “top‑N” sets: top users by reputation and by badge count
   ------------------------------------------------------------------ */
TopReputation AS (
    SELECT UserId, TotalReputation AS Metric, 'Reputation' AS MetricType
    FROM UserAggregates
    ORDER BY TotalReputation DESC
    LIMIT 50
),
TopBadge AS (
    SELECT ub.UserId, ub.TotalBadgeCount AS Metric, 'Badges' AS MetricType
    FROM UserBadges ub
    ORDER BY ub.TotalBadgeCount DESC
    LIMIT 50
),
TopCombined AS (
    SELECT * FROM TopReputation
    UNION ALL
    SELECT * FROM TopBadge
),

/* ------------------------------------------------------------------
   6️⃣  Final enriched view with window functions
   ------------------------------------------------------------------ */
EnrichedUsers AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.TotalReputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgQuestionScore,
        ua.AvgAnswerScore,
        ua.QuestionsWithAccepted,
        ub.GoldCount,
        ub.SilverCount,
        ub.BronzeCount,
        ub.TotalBadgeCount,
        ut.DistinctTagCount,
        ra.RecentQuestions,
        ra.RecentAnswers,
        ra.RecentUpvotes,
        ra.RecentDownvotes,
        /* Rank by reputation (dense) */
        DENSE_RANK() OVER (ORDER BY ua.TotalReputation DESC)   AS RepRank,
        /* Row‑number within each badge class tier (gold>silver>bronze) */
        ROW_NUMBER() OVER (
            PARTITION BY CASE 
                           WHEN ub.GoldCount > 0 THEN 'Gold'
                           WHEN ub.SilverCount > 0 THEN 'Silver'
                           ELSE 'Bronze'
                         END
            ORDER BY ub.TotalBadgeCount DESC
        )                                                       AS BadgeTierRow,
        /* Flag for users with no activity in the last 30 days */
        CASE 
            WHEN ra.RecentQuestions = 0 
                 AND ra.RecentAnswers = 0 
                 AND ra.RecentUpvotes = 0 
                 AND ra.RecentDownvotes = 0 THEN 1
            ELSE 0
        END                                                    AS Inactive30d
    FROM UserAggregates ua
    LEFT JOIN UserBadges ub            ON ub.UserId = ua.UserId
    LEFT JOIN UserTagUsage ut          ON ut.UserId = ua.UserId
    LEFT JOIN RecentActivity ra        ON ra.UserId = ua.UserId
)

SELECT
    eu.UserId,
    eu.DisplayName,
    eu.TotalReputation,
    eu.QuestionCount,
    eu.AnswerCount,
    eu.AvgQuestionScore,
    eu.AvgAnswerScore,
    eu.QuestionsWithAccepted,
    eu.GoldCount,
    eu.SilverCount,
    eu.BronzeCount,
    eu.TotalBadgeCount,
    eu.DistinctTagCount,
    eu.RecentQuestions,
    eu.RecentAnswers,
    eu.RecentUpvotes,
    eu.RecentDownvotes,
    eu.RepRank,
    eu.BadgeTierRow,
    eu.Inactive30d,
    tc.Metric,
    tc.MetricType
FROM EnrichedUsers eu
LEFT JOIN TopCombined tc
       ON tc.UserId = eu.UserId
ORDER BY eu.RepRank
LIMIT 100;
