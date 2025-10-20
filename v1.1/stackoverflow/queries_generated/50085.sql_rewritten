-- {"query": "50085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 832} 
WITH UserActivity AS (
    SELECT
        OwnerUserId,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN PostTypeId = 2 THEN Score ELSE 0 END) AS TotalAnswerScore,
        SUM(ViewCount) AS TotalViewCount,
        MIN(CreationDate) AS FirstPostDate,
        MAX(LastActivityDate) AS LastPostActivity
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND CreationDate > '2015-01-01'
    GROUP BY OwnerUserId
),
UserBadges AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserComments AS (
    SELECT
        UserId,
        COUNT(Id) AS CommentCount,
        SUM(Score) AS TotalCommentScore
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserCloseVotes AS (
    SELECT
        UserId,
        COUNT(Id) AS CloseVoteCount
    FROM PostHistory
    WHERE PostHistoryTypeId = 10 -- Post Closed
    AND UserId IS NOT NULL
    GROUP BY UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC, ub.GoldBadges DESC, ua.TotalAnswerScore DESC) AS ReputationRank,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalAnswerScore,
    COALESCE(ua.TotalAnswerScore / NULLIF(ua.AnswerCount, 0), 0) AS AvgAnswerScore,
    ua.TotalViewCount,
    EXTRACT(EPOCH FROM (ua.LastPostActivity - ua.FirstPostDate)) / 86400.0 AS ActiveDays,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    uc.CommentCount,
    uc.TotalCommentScore,
    ucv.CloseVoteCount,
    (
        SELECT AVG(p_inner.Score)
        FROM Posts p_inner
        WHERE p_inner.OwnerUserId = u.Id AND p_inner.PostTypeId = 2 -- Answers
    ) AS SubqueryAvgAnswerScore
FROM Users u
JOIN UserActivity ua ON u.Id = ua.OwnerUserId
LEFT JOIN UserBadges ub ON u.Id = ub.UserId
LEFT JOIN UserComments uc ON u.Id = uc.UserId
LEFT JOIN UserCloseVotes ucv ON u.Id = ucv.UserId
WHERE u.Reputation > 50000
  AND ua.AnswerCount > 100
  AND ub.GoldBadges > 5
  AND u.CreationDate < '2014-01-01'
  AND u.Id IN (
      SELECT DISTINCT p.OwnerUserId
      FROM Posts p
      JOIN Tags t ON p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId
      WHERE p.OwnerUserId IS NOT NULL AND t.Count > 10000
  )
ORDER BY ReputationRank, u.Reputation DESC
LIMIT 200;