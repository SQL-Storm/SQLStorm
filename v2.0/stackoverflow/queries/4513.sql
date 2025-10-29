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
              AND c.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
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
                  AND b.Class = 1
            ) THEN 'Expert'
            ELSE 'Standard'
        END AS BadgeStatus
    FROM Users u
    LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
    WHERE u.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '730 days')
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        LEAST(p.FavoriteCount, 100) AS LimitedFavoriteCount,
        CASE
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus,
        p.OwnerUserId,
        p.CreationDate,
        p.PostTypeId,
        p.ClosedDate,
        p.AcceptedAnswerId,
        p.FavoriteCount
    FROM Posts p
    WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
      AND p.PostTypeId IN (1, 2)
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
        pe.OwnerUserId,
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
    (lps.Score - lps.PreviousScore) AS ScoreDifference,
    lps.OwnerUserId
FROM UserActivity ua
JOIN LaggedPostScore lps ON ua.UserId = lps.OwnerUserId
WHERE ua.Reputation > 1000
  AND lps.RankWithinStatus <= 5
ORDER BY ua.Reputation DESC, ua.TotalAnswers DESC
LIMIT 50;