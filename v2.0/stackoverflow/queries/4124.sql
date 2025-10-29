-- {"query": "4124.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1107} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserPostCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserReputationHistory AS (
    SELECT
        UserId,
        CreationDate,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE -1 END) OVER (ORDER BY CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeReputationChange
    FROM Votes V
    WHERE V.VoteTypeId IN (2, 3) -- UpMod, DownMod
),
RecentHighScorePosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) as rnk
    FROM Posts p
    WHERE p.Score > 100
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(upc.TotalPosts, 0) AS TotalPostsCreated,
    COALESCE(upc.QuestionCount, 0) AS QuestionsAsked,
    COALESCE(upc.AnswerCount, 0) AS AnswersGiven,
    upc.AverageScore,
    CASE
        WHEN upc.LastPostDate IS NOT NULL THEN
            CASE
                WHEN upc.LastPostDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days' THEN 'Inactive'
                WHEN upc.LastPostDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days' THEN 'Moderately Active'
                ELSE 'Active'
            END
        ELSE 'No Posts'
    END AS ActivityStatus,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    rpeh.CreationDate AS LastEditDate,
    rpeh.PostHistoryTypeId AS LastEditType,
    COALESCE(urov.CumulativeReputationChange, u.Reputation) AS CurrentReputation,
    rhp.Title AS TopPostTitle,
    rhp.Score AS TopPostScore,
    COUNT(DISTINCT c.Id) AS CommentCountOnPosts
FROM Users u
LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
LEFT JOIN RankedPostEdits rpeh ON u.Id = rpeh.UserId AND rpeh.rn = 1
LEFT JOIN UserReputationHistory urov ON u.Id = urov.UserId
LEFT JOIN RecentHighScorePosts rhp ON u.Id = rhp.OwnerUserId AND rhp.rnk = 1
LEFT JOIN Posts p_user ON u.Id = p_user.OwnerUserId
LEFT JOIN Comments c ON p_user.Id = c.PostId
WHERE u.Id % 100 = 0 -- Sample a subset for performance testing
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    upc.TotalPosts,
    upc.QuestionCount,
    upc.AnswerCount,
    upc.AverageScore,
    upc.LastPostDate,
    rpeh.CreationDate,
    rpeh.PostHistoryTypeId,
    COALESCE(urov.CumulativeReputationChange, u.Reputation),
    rhp.Title,
    rhp.Score
HAVING COUNT(DISTINCT c.Id) > 5 -- Posts with more than 5 comments
ORDER BY u.Reputation DESC, u.CreationDate ASC;