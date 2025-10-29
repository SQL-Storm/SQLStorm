-- {"query": "3002.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1698} 

/*  Performance‑benchmarking query mixing CTEs, window functions, 
    outer joins, correlated subqueries, set operators and complex predicates   */
WITH 
-- 1️⃣ Aggregate badge counts per user and badge class
UserBadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount,
        COUNT(*)                                 AS TotalBadges,
        MAX(b.Date)                              AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),

-- 2️⃣ Compute per‑user post statistics (questions vs. answers) with windowed rank
UserPostStats AS (
    SELECT 
        p.OwnerUserId                                 AS UserId,
        COUNT(*) FILTER (WHERE pt.Name = 'Question') AS QuestionCount,
        COUNT(*) FILTER (WHERE pt.Name = 'Answer')   AS AnswerCount,
        AVG(p.Score)                                 AS AvgScore,
        SUM(p.ViewCount)                             AS TotalViews,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY p.CreationDate DESC) AS RecentPostRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

-- 3️⃣ Gather voting patterns for the most recent post per user
UserRecentVote AS (
    SELECT 
        up.UserId,
        v.VoteTypeId,
        COUNT(*) AS VoteCount
    FROM (
        SELECT 
            p.OwnerUserId AS UserId,
            p.Id         AS PostId,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                               ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
    ) up
    JOIN Votes v ON v.PostId = up.PostId AND up.rn = 1
    GROUP BY up.UserId, v.VoteTypeId
),

-- 4️⃣ Pull tag popularity for questions authored by each user (string parsing)
UserTagStats AS (
    SELECT 
        p.OwnerUserId                                           AS UserId,
        UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
        COUNT(*)                                                AS TagUseCount
    FROM Posts p
    WHERE p.PostTypeId = 1               -- only questions
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),

-- 5️⃣ Union of two dimensional analyses: badge‑rich users vs. tag‑rich users
CombinedUserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(b.GoldCount,0)    AS GoldBadges,
        COALESCE(b.SilverCount,0)  AS SilverBadges,
        COALESCE(b.BronzeCount,0)  AS BronzeBadges,
        COALESCE(p.QuestionCount,0) AS Questions,
        COALESCE(p.AnswerCount,0)   AS Answers,
        COALESCE(p.AvgScore,0)      AS AvgPostScore,
        COALESCE(t.TagUseCount,0)   AS TopTagUses,
        ROW_NUMBER() OVER (ORDER BY (COALESCE(b.GoldCount,0)*5
                                     +COALESCE(b.SilverCount,0)*3
                                     +COALESCE(b.BronzeCount,0)) DESC) AS BadgeRank,
        'BADGE' AS MetricSource
    FROM Users u
    LEFT JOIN UserBadgeAgg b      ON b.UserId = u.Id
    LEFT JOIN UserPostStats p     ON p.UserId = u.Id
    LEFT JOIN (
        SELECT UserId, MAX(TagUseCount) AS TagUseCount
        FROM UserTagStats
        GROUP BY UserId
    ) t                           ON t.UserId = u.Id
    WHERE u.Reputation > 1000

    UNION ALL

    SELECT 
        u.Id,
        u.DisplayName,
        0 AS GoldBadges,
        0 AS SilverBadges,
        0 AS BronzeBadges,
        0 AS Questions,
        0 AS Answers,
        0 AS AvgPostScore,
        COALESCE(t.TagUseCount,0) AS TopTagUses,
        ROW_NUMBER() OVER (ORDER BY COALESCE(t.TagUseCount,0) DESC) AS TagRank,
        'TAG' AS MetricSource
    FROM Users u
    LEFT JOIN (
        SELECT UserId, MAX(TagUseCount) AS TagUseCount
        FROM UserTagStats
        GROUP BY UserId
    ) t ON t.UserId = u.Id
    WHERE u.Id NOT IN (SELECT UserId FROM UserBadgeAgg)
      AND COALESCE(t.TagUseCount,0) > 5
)

SELECT 
    cm.Id,
    cm.DisplayName,
    cm.GoldBadges,
    cm.SilverBadges,
    cm.BronzeBadges,
    cm.Questions,
    cm.Answers,
    ROUND(cm.AvgPostScore,2)               AS AvgScore,
    cm.TopTagUses,
    cm.BadgeRank,
    cm.TagRank,
    cm.MetricSource,
    /* Correlated subquery: latest comment text (if any) on the user's most recent post */
    (SELECT LEFT(c.Text, 100)
     FROM Comments c
     JOIN Posts p ON p.Id = c.PostId
     WHERE p.OwnerUserId = cm.Id
       AND p.CreationDate = (SELECT MAX(CreationDate)
                             FROM Posts p2
                             WHERE p2.OwnerUserId = cm.Id)
     ORDER BY c.CreationDate DESC
     LIMIT 1) AS RecentCommentSnippet,
    /* NULL‑logic: flag if user has never voted on any post */
    CASE WHEN NOT EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = cm.Id) THEN 1 ELSE 0 END AS NeverVotedFlag,
    /* String expression: build a pseudo‑profile URL, handling NULLs */
    CONCAT('https://stackoverflow.com/users/', cm.Id, '/', COALESCE(REPLACE(cm.DisplayName,' ','-'),'anonymous')) AS ProfileUrl
FROM CombinedUserMetrics cm
ORDER BY 
    cm.MetricSource,
    CASE WHEN cm.MetricSource = 'BADGE' THEN cm.BadgeRank
         ELSE cm.TagRank END,
    cm.Id
LIMIT 100;
