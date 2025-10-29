-- {"query": "1391.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3310}
WITH PostEditCounts AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS TotalEditEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenedEvents,
        MAX(ph.CreationDate) AS LastContentEditTimestamp,
        MIN(ph.CreationDate) AS FirstHistoryEventTimestamp
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11)
    GROUP BY ph.PostId
    HAVING COUNT(DISTINCT ph.Id) >= 2
),
UserPostCommentStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p_own.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p_own.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN p_own.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COALESCE(SUM(p_own.Score), 0) AS TotalOwnedPostsScore,
        COUNT(DISTINCT c.PostId) AS DistinctPostsCommentedOn,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnOwnedPosts,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnOwnedPosts,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS UniqueUpvotersForOwnedPosts
    FROM Users u
    LEFT JOIN Posts p_own ON u.Id = p_own.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p_own.Id = v.PostId AND v.UserId IS NOT NULL
    GROUP BY u.Id
),
UserAcceptedAnswerStats AS (
    SELECT
        a.OwnerUserId AS UserId,
        AVG(CAST(a.Score AS DECIMAL)) AS AvgScoreOfAcceptedAnswers
    FROM Posts q
    JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
),
UserRecentGoldBadge AS (
    SELECT
        b.UserId,
        b.Name AS GoldBadgeName,
        b.Date AS GoldBadgeAwardDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Class = 1
),
UserTopAnswer AS (
    SELECT
        p_ans.OwnerUserId AS UserId,
        p_ans.Id AS TopAnswerId,
        p_ans.Score AS TopAnswerScore,
        SUBSTRING(REPLACE(p_ans.Body, CHR(10), ' ') FROM 1 FOR 250) AS TopAnswerBodyExcerpt,
        p_ques.Title AS ParentQuestionTitle,
        p_ques.Id AS ParentQuestionId,
        ROW_NUMBER() OVER (PARTITION BY p_ans.OwnerUserId ORDER BY p_ans.Score DESC, p_ans.CreationDate DESC) AS rn
    FROM Posts p_ans
    JOIN Posts p_ques ON p_ans.ParentId = p_ques.Id
    WHERE p_ans.PostTypeId = 2 AND p_ans.OwnerUserId IS NOT NULL
),
HighlyEngagedQuestions AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS PostOwnerUserId,
        p.Score AS PostScore,
        p.ViewCount,
        p.FavoriteCount,
        pec.TotalEditEvents,
        pec.ClosedEvents,
        pec.ReopenedEvents,
        EXTRACT(EPOCH FROM (pec.LastContentEditTimestamp - p.CreationDate)) AS TimeToLastEditSeconds,
        (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS QuestionDistinctUpvotersCount,
        COALESCE(p.Tags, '') AS PostTags,
        p.CreationDate AS PostCreationDate
    FROM Posts p
    JOIN PostEditCounts pec ON p.Id = pec.PostId
    WHERE p.PostTypeId = 1
      AND (LOWER(p.Title) LIKE '%api%' OR LOWER(p.Body) LIKE '%api%' OR LOWER(p.Tags) LIKE '%<api%>%')
      AND p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '4 years')
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(u.WebsiteUrl, 'N/A') AS UserWebsiteUrl,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    COALESCE(SUBSTRING(u.AboutMe FROM 1 FOR 200), 'No detailed description available.') AS AboutMeExcerpt,
    ups.TotalPostsOwned,
    ups.TotalQuestionsOwned,
    ups.TotalAnswersOwned,
    ups.TotalOwnedPostsScore,
    ups.DistinctPostsCommentedOn,
    ups.TotalCommentsMade,
    ups.TotalUpvotesReceivedOnOwnedPosts,
    ups.TotalDownvotesReceivedOnOwnedPosts,
    ups.UniqueUpvotersForOwnedPosts,
    COALESCE(uaas.AvgScoreOfAcceptedAnswers, 0.0) AS AverageAcceptedAnswerScore,
    COALESCE(rgb.GoldBadgeName, 'No Gold Badges') AS MostRecentGoldBadge,
    rgb.GoldBadgeAwardDate,
    tpa.TopAnswerId,
    tpa.TopAnswerScore,
    tpa.TopAnswerBodyExcerpt,
    tpa.ParentQuestionTitle,
    COUNT(heq.PostId) AS NumberOfHighlyEngagedQuestions,
    COALESCE(SUM(heq.PostScore), 0) AS TotalScoreOfEngagedQuestions,
    COALESCE(SUM(heq.ViewCount), 0) AS TotalViewCountOfEngagedQuestions,
    COALESCE(SUM(heq.FavoriteCount), 0) AS TotalFavoriteCountOfEngagedQuestions,
    COALESCE(AVG(heq.TimeToLastEditSeconds), 0) AS AvgTimeToLastEditSecondsForEngagedQuestions,
    COALESCE(SUM(heq.ClosedEvents), 0) AS TotalClosedEventsOnEngagedQuestions,
    COALESCE(SUM(heq.ReopenedEvents), 0) AS TotalReopenedEventsOnEngagedQuestions,
    CAST(
    (
        (u.Reputation * 0.05) +
        (ups.TotalUpvotesReceivedOnOwnedPosts * 0.7) -
        (ups.TotalDownvotesReceivedOnOwnedPosts * 0.3) +
        (ups.TotalCommentsMade * 0.1) +
        (ups.TotalQuestionsOwned * 0.8) +
        (ups.TotalAnswersOwned * 0.9) +
        (COALESCE(uaas.AvgScoreOfAcceptedAnswers, 0.0) * 1.8) +
        (COUNT(DISTINCT heq.PostId) * 2.5) +
        (COALESCE(SUM(heq.PostScore), 0) * 0.15) +
        (COALESCE(SUM(heq.FavoriteCount), 0) * 0.4) +
        (COALESCE(SUM(heq.ClosedEvents), 0) - COALESCE(SUM(heq.ReopenedEvents), 0)) * -1.0 +
        (CASE WHEN u.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(u.WebsiteUrl)) > 10 THEN 75 ELSE 0 END) +
        (CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) > 100 THEN 30 ELSE 0 END)
    ) AS DECIMAL
    ) AS EngagementScore,
    RANK() OVER (ORDER BY
        (
            (u.Reputation * 0.05) +
            (ups.TotalUpvotesReceivedOnOwnedPosts * 0.7) -
            (ups.TotalDownvotesReceivedOnOwnedPosts * 0.3) +
            (ups.TotalCommentsMade * 0.1) +
            (ups.TotalQuestionsOwned * 0.8) +
            (ups.TotalAnswersOwned * 0.9) +
            (COALESCE(uaas.AvgScoreOfAcceptedAnswers, 0.0) * 1.8) +
            (COUNT(DISTINCT heq.PostId) * 2.5) +
            (COALESCE(SUM(heq.PostScore), 0) * 0.15) +
            (COALESCE(SUM(heq.FavoriteCount), 0) * 0.4) +
            (COALESCE(SUM(heq.ClosedEvents), 0) - COALESCE(SUM(heq.ReopenedEvents), 0)) * -1.0 +
            (CASE WHEN u.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(u.WebsiteUrl)) > 10 THEN 75 ELSE 0 END) +
            (CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) > 100 THEN 30 ELSE 0 END)
        ) DESC, u.Reputation DESC, u.Id ASC) AS EngagementRank
FROM Users u
LEFT JOIN UserPostCommentStats ups ON u.Id = ups.UserId
LEFT JOIN UserAcceptedAnswerStats uaas ON u.Id = uaas.UserId
LEFT JOIN UserRecentGoldBadge rgb ON u.Id = rgb.UserId AND rgb.rn = 1
LEFT JOIN UserTopAnswer tpa ON u.Id = tpa.UserId AND tpa.rn = 1
LEFT JOIN HighlyEngagedQuestions heq ON u.Id = heq.PostOwnerUserId
WHERE u.Id IS NOT NULL
  AND u.Reputation > 2500
  AND u.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 years')
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.WebsiteUrl, u.Location, u.AboutMe,
    ups.TotalPostsOwned, ups.TotalQuestionsOwned, ups.TotalAnswersOwned, ups.TotalOwnedPostsScore,
    ups.DistinctPostsCommentedOn, ups.TotalCommentsMade,
    ups.TotalUpvotesReceivedOnOwnedPosts, ups.TotalDownvotesReceivedOnOwnedPosts, ups.UniqueUpvotersForOwnedPosts,
    uaas.AvgScoreOfAcceptedAnswers, rgb.GoldBadgeName, rgb.GoldBadgeAwardDate,
    tpa.TopAnswerId, tpa.TopAnswerScore, tpa.TopAnswerBodyExcerpt, tpa.ParentQuestionTitle
HAVING COUNT(heq.PostId) > 0
ORDER BY EngagementScore DESC, u.Reputation DESC
LIMIT 100;