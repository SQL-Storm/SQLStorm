-- {"query": "4513.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 965} 

WITH UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionCount,
        COUNT(CASE WHEN PostTypeId = 2 THEN Id END) AS AnswerCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(upc.QuestionCount, 0) AS TotalQuestions,
        COALESCE(upc.AnswerCount, 0) AS TotalAnswers,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.UserId = u.Id
            AND c.CreationDate >= DATE('now', '-365 day')
        ) AS RecentComments,
        CASE
            WHEN u.UpVotes > u.DownVotes * 2 THEN 'High'
            WHEN u.DownVotes > u.UpVotes * 2 THEN 'Low'
            ELSE 'Medium'
        END AS VoteRatioCategory,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM Badges b
                WHERE b.UserId = u.Id
                AND b.Name LIKE '%Expert%'
                AND b.Class = 1 -- Gold badge
            ) THEN 'Expert'
            ELSE 'Standard'
        END AS BadgeStatus
    FROM Users u
    LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
    WHERE u.CreationDate >= DATE('now', '-730 day')
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        LEAST(p.FavoriteCount, 100) AS LimitedFavoriteCount, -- Cap favorite count for performance
        CASE
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    WHERE p.CreationDate >= DATE('now', '-365 day')
    AND p.PostTypeId IN (1, 2) -- Questions and Answers
),
LaggedPostScore AS (
    SELECT
        pe.PostId,
        pe.Title,
        pe.Score,
        pe.ViewCount,
        pe.AnswerCount,
        pe.CommentCount,
        pe.LimitedFavoriteCount,
        pe.PostStatus,
        LAG(pe.Score, 1, 0) OVER (ORDER BY pe.Score DESC) AS PreviousScore,
        ROW_NUMBER() OVER (PARTITION BY pe.PostStatus ORDER BY pe.Score DESC, pe.ViewCount DESC) AS RankWithinStatus
    FROM PostEngagement pe
)
SELECT
    ua.DisplayName,
    ua.Reputation,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.RecentComments,
    ua.VoteRatioCategory,
    ua.BadgeStatus,
    lps.Title AS TopPostTitle,
    lps.Score AS TopPostScore,
    lps.ViewCount AS TopPostViewCount,
    lps.AnswerCount AS TopPostAnswerCount,
    lps.CommentCount AS TopPostCommentCount,
    lps.LimitedFavoriteCount AS TopPostLimitedFavoriteCount,
    lps.PostStatus AS TopPostStatus,
    (lps.Score - lps.PreviousScore) AS ScoreDifference
FROM UserActivity ua
JOIN LaggedPostScore lps ON ua.UserId = (
    SELECT OwnerUserId
    FROM Posts
    WHERE Id = (
        SELECT PostId
        FROM LaggedPostScore
        WHERE RankWithinStatus = 1
        ORDER BY Score DESC, ViewCount DESC
        LIMIT 1
    )
)
WHERE ua.Reputation > 1000 -- Only consider users with significant reputation
AND lps.RankWithinStatus <= 5 -- Consider top 5 posts per user if they meet criteria
ORDER BY ua.Reputation DESC, ua.TotalAnswers DESC
LIMIT 50;
