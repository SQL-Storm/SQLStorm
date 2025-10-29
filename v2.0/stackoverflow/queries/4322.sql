-- {"query": "4322.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1042}
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER(ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) AS RankByReputationAndActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= DATE '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScoreForOwner
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.CreationDate BETWEEN DATE '2015-01-01' AND DATE '2020-12-31'
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate
),
UserPostSummary AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.RankByReputationAndActivity,
        pe.PostId,
        pe.Title AS PostTitle,
        pe.Score AS PostScore,
        pe.PostStatus,
        pe.TotalCommentScore,
        pe.TotalVotes,
        pe.RankByScoreForOwner
    FROM RankedUserActivity rua
    JOIN PostEngagement pe ON rua.UserId = pe.OwnerUserId
    WHERE rua.RankByReputationAndActivity <= 100
)
SELECT
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.RankByReputationAndActivity,
    ups.PostId,
    ups.PostTitle,
    ups.PostScore,
    ups.PostStatus,
    ups.TotalCommentScore,
    ups.TotalVotes,
    ups.RankByScoreForOwner,
    CASE
        WHEN ups.PostScore > 100 THEN 'High Score'
        WHEN ups.PostScore BETWEEN 50 AND 100 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    UPPER(SUBSTRING(ups.PostTitle FROM 1 FOR 3)) AS TitlePrefix,
    (ups.TotalCommentScore * 1.5) + ups.TotalVotes AS EngagementMetric
FROM UserPostSummary ups
WHERE ups.RankByScoreForOwner <= 5
UNION ALL
SELECT
    NULL AS UserId,
    'Overall Average' AS DisplayName,
    AVG(ups.Reputation) AS Reputation,
    NULL AS RankByReputationAndActivity,
    NULL AS PostId,
    'Average Post Metrics' AS PostTitle,
    AVG(ups.PostScore) AS PostScore,
    NULL AS PostStatus,
    AVG(ups.TotalCommentScore) AS TotalCommentScore,
    AVG(ups.TotalVotes) AS TotalVotes,
    NULL AS RankByScoreForOwner,
    NULL AS ScoreCategory,
    NULL AS TitlePrefix,
    AVG((ups.TotalCommentScore * 1.5) + ups.TotalVotes) AS EngagementMetric
FROM UserPostSummary ups
WHERE ups.RankByReputationAndActivity <= 100 AND ups.RankByScoreForOwner <= 5
ORDER BY UserId NULLS LAST, RankByReputationAndActivity, RankByScoreForOwner;