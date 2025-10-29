-- {"query": "4417.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1088}
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        pht.Name AS HistoryTypeName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName
),
TopContributors AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.TotalPostsOwned,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgPostScore,
        ua.TotalComments,
        ua.TotalUpvotesReceived,
        ua.TotalDownvotesReceived,
        COUNT(rpe.PostId) AS EditsMade
    FROM UserActivity ua
    LEFT JOIN RankedPostEdits rpe ON ua.UserId = rpe.UserId AND rpe.rn = 1
    GROUP BY ua.UserId, ua.DisplayName, ua.TotalPostsOwned, ua.QuestionCount, ua.AnswerCount, ua.AvgPostScore, ua.TotalComments, ua.TotalUpvotesReceived, ua.TotalDownvotesReceived
    HAVING ua.TotalPostsOwned > 100 AND ua.TotalUpvotesReceived > 500
),
TopContributorsWithAdjusted AS (
    SELECT
        tc.UserId,
        tc.DisplayName,
        tc.TotalPostsOwned,
        tc.QuestionCount,
        tc.AnswerCount,
        tc.AvgPostScore,
        tc.TotalComments,
        tc.TotalUpvotesReceived,
        tc.TotalDownvotesReceived,
        tc.EditsMade,
        COALESCE(tc.AvgPostScore, 0) AS AdjustedAvgScore,
        UPPER(SUBSTRING(tc.DisplayName FROM 1 FOR 3)) AS DisplayPrefix,
        CASE
            WHEN tc.TotalPostsOwned > 5000 THEN 'Veteran'
            WHEN tc.TotalPostsOwned > 1000 THEN 'Experienced'
            ELSE 'Newer'
        END AS UserTier,
        (tc.TotalUpvotesReceived - tc.TotalDownvotesReceived) AS NetVotes,
        CASE
            WHEN tc.EditsMade > 0 AND tc.TotalPostsOwned > 0 THEN CAST(tc.EditsMade AS DECIMAL) / tc.TotalPostsOwned * 100
            ELSE 0.00
        END AS EditPercentage
    FROM TopContributors tc
)
SELECT
    tc.DisplayName,
    tc.TotalPostsOwned,
    tc.QuestionCount,
    tc.AnswerCount,
    tc.EditsMade,
    tc.AdjustedAvgScore,
    tc.TotalComments,
    tc.TotalUpvotesReceived,
    tc.TotalDownvotesReceived,
    tc.DisplayPrefix,
    tc.UserTier,
    tc.NetVotes,
    ROUND(tc.EditPercentage, 2) AS EditPercentageRounded,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tc.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tc.UserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tc.UserId AND b.Class = 3) AS BronzeBadges
FROM TopContributorsWithAdjusted tc
WHERE tc.DisplayName IS NOT NULL

UNION ALL

SELECT
    'OverallAverage' AS DisplayName,
    AVG(CAST(TotalPostsOwned AS DECIMAL)) AS TotalPostsOwned,
    AVG(CAST(QuestionCount AS DECIMAL)) AS QuestionCount,
    AVG(CAST(AnswerCount AS DECIMAL)) AS AnswerCount,
    AVG(CAST(EditsMade AS DECIMAL)) AS EditsMade,
    AVG(CAST(AdjustedAvgScore AS DECIMAL)) AS AdjustedAvgScore,
    AVG(CAST(TotalComments AS DECIMAL)) AS TotalComments,
    AVG(CAST(TotalUpvotesReceived AS DECIMAL)) AS TotalUpvotesReceived,
    AVG(CAST(TotalDownvotesReceived AS DECIMAL)) AS TotalDownvotesReceived,
    CAST(NULL AS VARCHAR(100)) AS DisplayPrefix,
    CAST(NULL AS VARCHAR(50)) AS UserTier,
    CAST(NULL AS DECIMAL) AS NetVotes,
    CAST(NULL AS DECIMAL) AS EditPercentageRounded,
    CAST(NULL AS INTEGER) AS GoldBadges,
    CAST(NULL AS INTEGER) AS SilverBadges,
    CAST(NULL AS INTEGER) AS BronzeBadges
FROM TopContributorsWithAdjusted
WHERE DisplayName <> 'OverallAverage'
ORDER BY TotalPostsOwned DESC;