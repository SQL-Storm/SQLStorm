-- {"query": "50100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1279} 

WITH TagSpecificPosts AS (
    -- 1. Filter posts for a popular and specific tag ('sql' in this case)
    SELECT Id, OwnerUserId, PostTypeId, Score, ViewCount, CreationDate, ParentId, AcceptedAnswerId
    FROM Posts
    WHERE Tags LIKE '%<sql>%' AND OwnerUserId IS NOT NULL
),
UserActivitySummary AS (
    -- 2. Aggregate user activity within that tag
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(tsp.Id) AS TotalPostsInTag,
        SUM(CASE WHEN tsp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN tsp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(tsp.Score) AS TotalScoreInTag,
        AVG(tsp.Score) AS AvgScoreInTag,
        SUM(tsp.ViewCount) AS TotalViewCountInTag,
        MIN(tsp.CreationDate) AS FirstPostDateInTag,
        MAX(tsp.CreationDate) AS LastPostDateInTag
    FROM Users u
    JOIN TagSpecificPosts tsp ON u.Id = tsp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(tsp.Id) > 20 AND SUM(CASE WHEN tsp.PostTypeId = 2 THEN 1 ELSE 0 END) > 5 -- Filter for active users
),
AcceptedAnswerStats AS (
    -- 3. Calculate accepted answer statistics for these users
    SELECT
        ans.OwnerUserId as UserId,
        COUNT(ans.Id) AS AcceptedAnswers,
        AVG(ans.Score) AS AvgScoreOfAcceptedAnswers
    FROM Posts AS que
    JOIN Posts AS ans ON que.AcceptedAnswerId = ans.Id
    WHERE que.Id IN (SELECT Id FROM TagSpecificPosts WHERE PostTypeId = 1) -- Questions must be in the target tag
    GROUP BY ans.OwnerUserId
),
UserBadgeDetails AS (
    -- 4. Get badge counts for each user
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserEngagement AS (
    -- 5. Measure user engagement through votes and comments on tag-specific posts
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS CommentsInTag,
        COUNT(DISTINCT v.Id) AS VotesInTag
    FROM TagSpecificPosts tsp
    LEFT JOIN Comments c ON tsp.Id = c.PostId
    LEFT JOIN Votes v ON tsp.Id = v.PostId AND v.UserId = c.UserId -- Correlate user's comments and votes
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
RankedUsers AS (
    -- 6. Combine all metrics and rank users
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPostsInTag,
        uas.QuestionCount,
        uas.AnswerCount,
        COALESCE(aas.AcceptedAnswers, 0) AS AcceptedAnswerCount,
        CAST(COALESCE(aas.AcceptedAnswers, 0) AS DECIMAL) / NULLIF(uas.AnswerCount, 0) AS AcceptanceRate,
        uas.TotalScoreInTag,
        uas.AvgScoreInTag,
        ubd.GoldBadges,
        ubd.SilverBadges,
        ubd.BronzeBadges,
        ue.CommentsInTag,
        ue.VotesInTag,
        extract(epoch from (uas.LastPostDateInTag - uas.FirstPostDateInTag)) / 86400.0 AS ActivityPeriodDays,
        (uas.TotalScoreInTag * 0.4) + (COALESCE(aas.AcceptedAnswers, 0) * 0.3) + (uas.Reputation * 0.1) + (COALESCE(ubd.GoldBadges, 0) * 0.2) AS WeightedScore,
        AVG(uas.TotalScoreInTag) OVER (PARTITION BY ubd.GoldBadges) AS AvgTagScoreForGoldBadgeTier
    FROM UserActivitySummary uas
    LEFT JOIN AcceptedAnswerStats aas ON uas.UserId = aas.UserId
    LEFT JOIN UserBadgeDetails ubd ON uas.UserId = ubd.UserId
    LEFT JOIN UserEngagement ue ON uas.UserId = ue.UserId
    WHERE uas.Reputation > 10000
)
-- 7. Final selection and ordering
SELECT
    DisplayName,
    Reputation,
    TotalPostsInTag,
    AnswerCount,
    AcceptedAnswerCount,
    AcceptanceRate,
    TotalScoreInTag,
    WeightedScore,
    GoldBadges,
    SilverBadges,
    CommentsInTag,
    VotesInTag,
    ActivityPeriodDays,
    TotalScoreInTag - AvgTagScoreForGoldBadgeTier AS ScoreDeltaFromTierAverage,
    ROW_NUMBER() OVER (ORDER BY WeightedScore DESC, Reputation DESC) AS OverallRank
FROM RankedUsers
WHERE
    AcceptanceRate > 0.15 OR TotalScoreInTag > 500
ORDER BY
    OverallRank
LIMIT 200;
