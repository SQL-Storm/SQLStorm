-- {"query": "20069.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1335} 
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate) AS UserAge,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 1000 AND u.LastAccessDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostMetrics AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS TotalAnswerScore,
        AVG(p.CommentCount) AS AvgPostCommentCount,
        MAX(p.FavoriteCount) AS MaxPostFavoriteCount,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM
        Posts p
    LEFT JOIN
        Posts q ON p.ParentId = q.Id
    WHERE
        p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
),
UserTemporalBehavior AS (
    SELECT
        OwnerUserId,
        AVG(TimeBetweenPosts) AS AvgTimeBetweenPostsInHours
    FROM (
        SELECT
            OwnerUserId,
            EXTRACT(EPOCH FROM (CreationDate - LAG(CreationDate, 1) OVER (PARTITION BY OwnerUserId ORDER BY CreationDate))) / 3600.0 AS TimeBetweenPosts
        FROM
            Posts
        WHERE OwnerUserId IS NOT NULL
    ) AS PostIntervals
    WHERE
        TimeBetweenPosts IS NOT NULL AND TimeBetweenPosts < 720 -- Ignore gaps longer than 30 days
    GROUP BY
        OwnerUserId
)
SELECT
    uas.DisplayName,
    uas.Reputation,
    pm.QuestionCount,
    pm.AnswerCount,
    pm.AcceptedAnswerCount,
    COALESCE(pm.AcceptedAnswerCount * 100.0 / NULLIF(pm.AnswerCount, 0), 0) AS AcceptanceRate,
    (SELECT STRING_AGG(DISTINCT t.TagName, ', ') FROM Tags t WHERE t.Id IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.Tags IS NOT NULL ORDER BY p.Score DESC LIMIT 5)) AS TopTags,
    -- Correlated subquery to find the post with the longest title
    (SELECT
        SUBSTRING(p_inner.Title FROM 1 FOR 50) || '...'
     FROM Posts p_inner
     WHERE p_inner.OwnerUserId = uas.UserId AND p_inner.PostTypeId = 1
     ORDER BY LENGTH(p_inner.Title) DESC
     LIMIT 1) AS LongestQuestionTitle,
    -- Complex engagement score calculation
    LN(uas.Reputation + 1) * (
        (COALESCE(pm.AnswerCount, 0) * 1.2) +
        (COALESCE(pm.QuestionCount, 0) * 0.8) +
        (uas.GoldBadges * 10) +
        (uas.SilverBadges * 3)
    ) / (EXTRACT(EPOCH FROM uas.UserAge) / (3600*24*365.25)) AS EngagementScore,
    -- Window function to rank users
    RANK() OVER (ORDER BY LN(uas.Reputation + 1) * (
        (COALESCE(pm.AnswerCount, 0) * 1.2) +
        (COALESCE(pm.QuestionCount, 0) * 0.8) +
        (uas.GoldBadges * 10) +
        (uas.SilverBadges * 3)
    ) / (EXTRACT(EPOCH FROM uas.UserAge) / (3600*24*365.25)) DESC) AS UserRank
FROM
    UserActivitySummary uas
JOIN
    PostMetrics pm ON uas.UserId = pm.OwnerUserId
LEFT JOIN
    UserTemporalBehavior utb ON uas.UserId = utb.OwnerUserId
WHERE
    pm.AnswerCount > pm.QuestionCount
    AND uas.GoldBadges > 0
    AND uas.UserId IN ( -- Subquery with a set operator
        SELECT UserId FROM Comments WHERE Score > 5
        INTERSECT
        SELECT UserId FROM Votes WHERE VoteTypeId = 5 -- Favorite vote
    )
    AND EXISTS ( -- Correlated subquery checking for answers to highly-viewed questions
        SELECT 1
        FROM Posts ans
        JOIN Posts q ON ans.ParentId = q.Id
        WHERE ans.OwnerUserId = uas.UserId
        AND q.ViewCount > 10000
        AND q.ClosedDate IS NULL
    )
ORDER BY
    UserRank ASC, uas.Reputation DESC
LIMIT 200;