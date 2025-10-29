-- {"query": "3567.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2395} 
WITH
    -- Badge aggregates per user
    BadgeAgg AS (
        SELECT
            u.Id                         AS UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            COUNT(*)                     AS TotalBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),

    -- Post aggregates per user
    PostAgg AS (
        SELECT
            u.Id                         AS UserId,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
            MAX(p.CreationDate)          AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id
    ),

    -- Most recent post per user (using window function)
    RecentPost AS (
        SELECT
            p.OwnerUserId,
            p.Id           AS RecentPostId,
            p.Title,
            p.CreationDate,
            p.Score,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
    ),

    -- Tag frequencies for answers (splitting the Tags column)
    UserTagAgg AS (
        SELECT
            a.OwnerUserId                     AS UserId,
            unnest(string_to_array(trim(both '<>' FROM q.Tags), '><')) AS Tag,
            COUNT(*)                          AS AnswersInTag
        FROM Posts q
        JOIN Posts a ON a.ParentId = q.Id          -- a is an answer to question q
        WHERE a.PostTypeId = 2
          AND a.OwnerUserId IS NOT NULL
          AND q.Tags IS NOT NULL
        GROUP BY a.OwnerUserId, Tag
    ),

    -- Top 3 tags per user concatenated as a string
    TopTags AS (
        SELECT
            UserId,
            STRING_AGG(Tag || ':' || AnswersInTag, ', ') 
                FILTER (WHERE rn <= 3) AS Top3Tags
        FROM (
            SELECT
                UserId,
                Tag,
                AnswersInTag,
                ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY AnswersInTag DESC) AS rn
            FROM UserTagAgg
        ) t
        GROUP BY UserId
    ),

    -- Combine all metrics, add ranking and activity flag
    UserMetrics AS (
        SELECT
            u.Id,
            COALESCE(u.DisplayName, 'Anonymous')      AS DisplayName,
            u.Reputation,
            COALESCE(b.GoldBadges,0)                  AS GoldBadges,
            COALESCE(b.SilverBadges,0)                AS SilverBadges,
            COALESCE(b.BronzeBadges,0)                AS BronzeBadges,
            COALESCE(p.QuestionCount,0)               AS QuestionCount,
            COALESCE(p.AnswerCount,0)                 AS AnswerCount,
            ROUND(COALESCE(p.AvgAnswerScore,0)::numeric,2) AS AvgAnswerScore,
            COALESCE(t.Top3Tags,'')                   AS Top3Tags,
            rp.Title                                  AS RecentPostTitle,
            rp.Score                                  AS RecentPostScore,
            rp.CreationDate                           AS RecentPostDate,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC,
                                         COALESCE(b.GoldBadges,0) DESC) AS ReputationRank
        FROM Users u
        LEFT JOIN BadgeAgg b       ON b.UserId = u.Id
        LEFT JOIN PostAgg p        ON p.UserId = u.Id
        LEFT JOIN TopTags t        ON t.UserId = u.Id
        LEFT JOIN (
            SELECT OwnerUserId, Title, Score, CreationDate
            FROM RecentPost
            WHERE rn = 1
        ) rp ON rp.OwnerUserId = u.Id
    )

SELECT
    um.Id,
    um.DisplayName,
    um.Reputation,
    um.ReputationRank,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    um.QuestionCount,
    um.AnswerCount,
    um.AvgAnswerScore,
    um.Top3Tags,
    um.RecentPostTitle,
    um.RecentPostScore,
    um.RecentPostDate,
    CASE
        WHEN um.RecentPostDate IS NULL                     THEN 'No recent activity'
        WHEN um.RecentPostDate < cast('2024-10-01' as date) - INTERVAL '1 year' THEN 'Stale'
        ELSE 'Active'
    END AS ActivityStatus
FROM UserMetrics um
WHERE um.ReputationRank <= 100
   OR (um.GoldBadges > 0 AND um.AnswerCount > 50)
ORDER BY um.ReputationRank;