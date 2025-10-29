-- {"query": "3731.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1745} 

/*  Complex performance‑benchmark query for the StackOverflow schema  */
WITH
/* 1️⃣ Aggregate per‑user post statistics, using LEFT JOIN to keep users without posts */
UserStats AS (
    SELECT
        u.Id                           AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                  FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id)                  FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score)                                    AS TotalScore,
        MAX(p.CreationDate)                             AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* 2️⃣ Badge totals per user, using conditional aggregation */
BadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

/* 3️⃣ Votes a user gave in the last 30 days (correlated sub‑query style) */
RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*) AS VoteGivenCount
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),

/* 4️⃣ Most frequent tag a user has used (string parsing + correlated sub‑query) */
TopTagUsage AS (
    SELECT
        p.OwnerUserId AS UserId,
        (
            SELECT t.TagName
            FROM regexp_split_to_table(p.Tags, '[><]') AS tag
            JOIN Tags t ON t.TagName = tag
            GROUP BY t.TagName
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) AS TopTag
    FROM Posts p
    WHERE p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
),

/* 5️⃣ Combine everything, add window functions for ranking and percentiles */
RankedUsers AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        COALESCE(bc.GoldBadges,   0) AS GoldBadges,
        COALESCE(bc.SilverBadges, 0) AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(rv.VoteGivenCount, 0) AS RecentVotes,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        tu.TopTag,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalScore DESC) AS ReputationRank,
        PERCENT_RANK() OVER (ORDER BY us.TotalScore)                           AS ScorePercentile
    FROM UserStats   us
    LEFT JOIN BadgeCounts   bc ON bc.UserId = us.UserId
    LEFT JOIN RecentVotes   rv ON rv.UserId = us.UserId
    LEFT JOIN TopTagUsage   tu ON tu.UserId = us.UserId
)

/* --------------------------------------------------------------- */
/* Final result set: top users plus a summary row (set operator)   */
/* --------------------------------------------------------------- */
SELECT *
FROM RankedUsers
WHERE ReputationRank <= 100
   OR (GoldBadges >= 5 AND ScorePercentile > 0.9)
ORDER BY ReputationRank

UNION ALL

SELECT
    NULL          AS UserId,
    'TOTAL'       AS DisplayName,
    SUM(Reputation)           AS Reputation,
    SUM(GoldBadges)           AS GoldBadges,
    SUM(SilverBadges)         AS SilverBadges,
    SUM(BronzeBadges)         AS BronzeBadges,
    SUM(RecentVotes)          AS RecentVotes,
    SUM(QuestionCount)        AS QuestionCount,
    SUM(AnswerCount)          AS AnswerCount,
    SUM(TotalScore)           AS TotalScore,
    NULL          AS TopTag,
    NULL          AS ReputationRank,
    NULL          AS ScorePercentile
FROM RankedUsers
WHERE ReputationRank <= 100;
