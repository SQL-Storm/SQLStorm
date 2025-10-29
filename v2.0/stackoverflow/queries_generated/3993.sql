-- {"query": "3993.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1620} 

/*  Benchmark query: heavy use of CTEs, window functions, outer joins, 
    set operators, correlated subqueries, string ops and NULL logic  */
WITH 
-- 1. Basic per‑user activity aggregates
UserStats AS (
    SELECT 
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                            AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)   AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)   AS AnswerCount,
        AVG(p.Score)                           AS AvgPostScore,
        MAX(p.CreationDate)                    AS LastPostDate,
        COALESCE(MAX(p.LastActivityDate), u.LastAccessDate) AS LastActivity,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),

-- 2. Tag usage per user (derived from the Tags column of questions)
TagUsage AS (
    SELECT 
        u.Id                                   AS UserId,
        LOWER(TRIM(t.Tag))                     AS Tag,
        COUNT(*)                               AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p
        ON p.OwnerUserId = u.Id
       AND p.PostTypeId = 1                -- only questions
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(
                 TRIM(BOTH '<>' FROM p.Tags), 
                 '><'
               ) AS Tag
    ) t
    GROUP BY u.Id, LOWER(TRIM(t.Tag))
),

-- 3. Badge aggregation per user, split by class (gold/silver/bronze)
BadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*)                                      AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),

-- 4. Recent voting activity (last 30 days) with vote type breakdown
RecentVotes AS (
    SELECT 
        v.PostId,
        p.OwnerUserId                           AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes30d,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes30d,
        MAX(v.CreationDate)                     AS LastVoteDate
    FROM Votes v
    JOIN Posts p
        ON p.Id = v.PostId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId, p.OwnerUserId
),

-- 5. Users with no posts (to be unioned later)
NoPostUsers AS (
    SELECT 
        u.Id           AS UserId,
        u.DisplayName,
        u.Reputation,
        0              AS TotalPosts,
        0              AS QuestionCount,
        0              AS AnswerCount,
        NULL           AS AvgPostScore,
        NULL           AS LastPostDate,
        u.LastAccessDate AS LastActivity,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
)

-- 6. Combine users with and without posts, preferring those with activity
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.RepRank,
    us.TotalPosts,
    us.QuestionCount,
    us.AnswerCount,
    ROUND(us.AvgPostScore::numeric, 2)               AS AvgScore,
    us.LastPostDate,
    us.LastActivity,
    COALESCE(b.GoldBadges,0)                         AS GoldBadges,
    COALESCE(b.SilverBadges,0)                       AS SilverBadges,
    COALESCE(b.BronzeBadges,0)                       AS BronzeBadges,
    COALESCE(rv.UpVotes30d,0)                        AS UpVotesLast30d,
    COALESCE(rv.DownVotes30d,0)                      AS DownVotesLast30d,
    /* Most used tag (if any) */
    (SELECT tu.Tag
       FROM TagUsage tu
       WHERE tu.UserId = us.UserId
         AND tu.TagRank = 1)                         AS TopTag,
    /* Correlated subquery: title of the most recent question */
    (SELECT p.Title
       FROM Posts p
       WHERE p.OwnerUserId = us.UserId
         AND p.PostTypeId = 1
       ORDER BY p.CreationDate DESC
       LIMIT 1)                                      AS RecentQuestionTitle,
    /* Boolean flag: has earned at least one gold badge and > 5k reputation */
    CASE 
        WHEN COALESCE(b.GoldBadges,0) > 0 AND us.Reputation > 5000 THEN true
        ELSE false
    END                                            AS EliteUserFlag
FROM UserStats us
LEFT JOIN BadgeAgg b
       ON b.UserId = us.UserId
LEFT JOIN RecentVotes rv
       ON rv.UserId = us.UserId
UNION ALL
SELECT 
    npu.UserId,
    npu.DisplayName,
    npu.Reputation,
    npu.RepRank,
    npu.TotalPosts,
    npu.QuestionCount,
    npu.AnswerCount,
    NULL,
    npu.LastPostDate,
    npu.LastActivity,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS UpVotesLast30d,
    0 AS DownVotesLast30d,
    NULL AS TopTag,
    NULL AS RecentQuestionTitle,
    false AS EliteUserFlag
FROM NoPostUsers npu
ORDER BY RepRank
LIMIT 1000;
