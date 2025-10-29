-- {"query": "3578.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1650} 

/*  Complex benchmark query using CTEs, window functions, outer joins,
    correlated subqueries, set operators and extensive NULL/STRING logic  */
WITH RECURSIVE
    -- 1️⃣  Gather every answer with its tags exploded, handling NULL tags gracefully
    exploded_answers AS (
        SELECT
            a.Id               AS AnswerId,
            a.OwnerUserId      AS UserId,
            a.CreationDate,
            a.Score            AS AnswerScore,
            COALESCE(
                /* Tags are stored like "<tag1><tag2>", strip the outer <> and split */
                regexp_split_to_table(substr(a.Tags, 2, length(a.Tags)-2), '><'),
                NULL
            )                  AS Tag
        FROM Posts a
        WHERE a.PostTypeId = 2                         -- only answers
    ),

    -- 2️⃣  Aggregate tag‑level answer statistics per user
    user_tag_stats AS (
        SELECT
            ua.UserId,
            ua.Tag,
            COUNT(*)                           AS AnswersPerTag,
            SUM(ua.AnswerScore)                AS TotalScorePerTag,
            AVG(ua.AnswerScore)                AS AvgScorePerTag,
            ROW_NUMBER() OVER (
                PARTITION BY ua.UserId
                ORDER BY COUNT(*) DESC, SUM(ua.AnswerScore) DESC
            )                                  AS TagRank
        FROM exploded_answers ua
        GROUP BY ua.UserId, ua.Tag
    ),

    -- 3️⃣  Count badges per class (Gold=1, Silver=2, Bronze=3) for each user
    badge_counts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            COUNT(*)                                        AS TotalBadges
        FROM Badges b
        GROUP BY b.UserId
    ),

    -- 4️⃣  Latest activity per user (posts, comments, votes)
    latest_activity AS (
        SELECT
            u.Id                                       AS UserId,
            GREATEST(
                COALESCE(p.LastActivityDate, TIMESTAMP '1970-01-01'),
                COALESCE(c.CreationDate,    TIMESTAMP '1970-01-01'),
                COALESCE(v.CreationDate,    TIMESTAMP '1970-01-01')
            )                                          AS LastActivity
        FROM Users u
        LEFT JOIN (
            SELECT OwnerUserId, MAX(LastActivityDate) AS LastActivityDate
            FROM Posts
            GROUP BY OwnerUserId
        ) p ON p.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT UserId, MAX(CreationDate) AS CreationDate
            FROM Comments
            GROUP BY UserId
        ) c ON c.UserId = u.Id
        LEFT JOIN (
            SELECT UserId, MAX(CreationDate) AS CreationDate
            FROM Votes
            GROUP BY UserId
        ) v ON v.UserId = u.Id
    ),

    -- 5️⃣  Users with *any* activity (posts, comments, votes, badges)
    active_users AS (
        SELECT DISTINCT u.Id AS UserId
        FROM Users u
        LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN Votes v    ON v.UserId = u.Id
        LEFT JOIN Badges b   ON b.UserId = u.Id
        WHERE p.Id IS NOT NULL
           OR c.Id IS NOT NULL
           OR v.Id IS NOT NULL
           OR b.Id IS NOT NULL
    ),

    -- 6️⃣  Users who only have badges but no posts/comments/votes
    badge_only_users AS (
        SELECT u.Id AS UserId
        FROM Users u
        JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN Votes v    ON v.UserId = u.Id
        WHERE p.Id IS NULL AND c.Id IS NULL AND v.Id IS NULL
    ),

    -- 7️⃣  Union of all users we want to assess
    all_considered_users AS (
        SELECT UserId FROM active_users
        UNION
        SELECT UserId FROM badge_only_users
    )

SELECT
    u.Id                                    AS UserId,
    COALESCE(u.DisplayName, '[deleted]')    AS DisplayName,
    u.Reputation,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    bc.TotalBadges,
    ut.Tag                                   AS TopTag,
    ut.AnswersPerTag                         AS AnswersOnTopTag,
    ROUND(ut.AvgScorePerTag::numeric,2)     AS AvgScoreOnTopTag,
    la.LastActivity,
    /* Correlated subquery: distinct days the user posted any answer */
    (SELECT COUNT(DISTINCT DATE(a.CreationDate))
     FROM Posts a
     WHERE a.PostTypeId = 2
       AND a.OwnerUserId = u.Id)            AS DistinctAnswerDays,
    /* Window function: user's rank by reputation among all considered users */
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
FROM all_considered_users acu
JOIN Users u          ON u.Id = acu.UserId
LEFT JOIN badge_counts bc   ON bc.UserId = u.Id
LEFT JOIN latest_activity la ON la.UserId = u.Id
LEFT JOIN (
    SELECT UserId, Tag, AnswersPerTag, AvgScorePerTag
    FROM user_tag_stats
    WHERE TagRank = 1                -- keep only the top tag per user
) ut ON ut.UserId = u.Id
ORDER BY u.Reputation DESC
LIMIT 100;
