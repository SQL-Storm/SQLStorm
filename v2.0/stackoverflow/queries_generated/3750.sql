-- {"query": "3750.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2343} 

WITH 
-- 1. Basic user statistics, including badge counts and recent activity
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0)               AS UpVotes,
        COALESCE(u.DownVotes,0)             AS DownVotes,
        (COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)) AS VoteBalance,
        CASE 
            WHEN COALESCE(u.DownVotes,0)=0 THEN NULL 
            ELSE CAST(COALESCE(u.UpVotes,0) AS FLOAT)/COALESCE(u.DownVotes,0) 
        END                                 AS UpDownRatio,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT MAX(CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
),

-- 2. Per‑user post aggregation using FILTER (Postgres syntax) for questions vs answers
UserPostAgg AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS QuestionScore,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AnswerScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    GROUP BY p.OwnerUserId
),

-- 3. Top tags overall (used for ranking later)
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),

-- 4. Extract each user's most frequent tag across their questions
UserTopTag AS (
    SELECT 
        us.Id AS UserId,
        tt.TagName,
        tt.Count AS TagUseCount,
        tt.TagRank
    FROM UserStats us
    LEFT JOIN LATERAL (
        SELECT 
            tg.TagName,
            tg.Count,
            ROW_NUMBER() OVER (ORDER BY tg.Count DESC) AS rn
        FROM (
            SELECT 
                UNNEST(string_to_array(regexp_replace(p.Tags,'[<>]','', 'g'), ' ')) AS Tag
            FROM Posts p
            WHERE p.OwnerUserId = us.Id AND p.PostTypeId = 1
        ) AS extracted
        JOIN Tags tg ON tg.TagName = extracted.Tag
        GROUP BY tg.TagName, tg.Count
        ORDER BY tg.Count DESC
        LIMIT 1
    ) tt ON TRUE
)

SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.VoteBalance,
    us.UpDownRatio,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    COALESCE(upa.QuestionCount,0)           AS QuestionsPosted,
    COALESCE(upa.AnswerCount,0)            AS AnswersPosted,
    COALESCE(upa.QuestionScore,0)          AS QuestionScore,
    COALESCE(upa.AnswerScore,0)            AS AnswerScore,
    us.LastPostDate,
    CASE
        WHEN us.LastPostDate IS NULL                 THEN 'Never'
        WHEN us.LastPostDate < CURRENT_DATE - INTERVAL '1 year' THEN 'Stale'
        ELSE 'Active'
    END                                      AS ActivityStatus,
    ut.TagName,
    ut.TagUseCount,
    ut.TagRank
FROM UserStats us
LEFT JOIN UserPostAgg upa   ON upa.UserId = us.Id
LEFT JOIN UserTopTag ut    ON ut.UserId = us.Id
WHERE us.Reputation > 1000
  AND (us.GoldBadges + us.SilverBadges + us.BronzeBadges) > 0

UNION ALL

-- 5. Global aggregate row for the same filtered set
SELECT 
    NULL                                       AS Id,
    'Aggregate'                                 AS DisplayName,
    SUM(us.Reputation)                          AS Reputation,
    SUM(us.VoteBalance)                         AS VoteBalance,
    AVG(us.UpDownRatio)                         AS UpDownRatio,
    SUM(us.GoldBadges)                          AS GoldBadges,
    SUM(us.SilverBadges)                        AS SilverBadges,
    SUM(us.BronzeBadges)                        AS BronzeBadges,
    SUM(COALESCE(upa.QuestionCount,0))           AS QuestionsPosted,
    SUM(COALESCE(upa.AnswerCount,0))            AS AnswersPosted,
    SUM(COALESCE(upa.QuestionScore,0))          AS QuestionScore,
    SUM(COALESCE(upa.AnswerScore,0))            AS AnswerScore,
    NULL                                        AS LastPostDate,
    NULL                                        AS ActivityStatus,
    NULL                                        AS TagName,
    NULL                                        AS TagUseCount,
    NULL                                        AS TagRank
FROM UserStats us
LEFT JOIN UserPostAgg upa ON upa.UserId = us.Id
WHERE us.Reputation > 1000
  AND (us.GoldBadges + us.SilverBadges + us.BronzeBadges) > 0

ORDER BY Reputation DESC
LIMIT 100;
