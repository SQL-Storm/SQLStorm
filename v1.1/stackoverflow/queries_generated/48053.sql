-- {"query": "48053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 613} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 ELSE 0 END) AS ModerationActionCount,
        AVG(CASE WHEN rp.Score IS NOT NULL THEN rp.Score ELSE 0 END) AS AvgQuestionScore,
        SUM(CASE WHEN rp.rn = 1 THEN 1 ELSE 0 END) AS IsTopPoster
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId AND rp.rn <= 5
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.PostHistoryCount,
    ua.EditCount,
    ua.ModerationActionCount,
    ua.AvgQuestionScore,
    ua.IsTopPoster,
    AVG(p.Score) AS AvgPostScore,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestions
FROM UserActivity ua
JOIN Posts p ON ua.UserId = p.OwnerUserId
WHERE ua.Reputation > 1000 AND ua.UserCreationDate < '2023-01-01'
GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.UserCreationDate, ua.PostHistoryCount, ua.EditCount, ua.ModerationActionCount, ua.AvgQuestionScore, ua.IsTopPoster
ORDER BY ua.Reputation DESC, TotalPosts DESC
LIMIT 100;