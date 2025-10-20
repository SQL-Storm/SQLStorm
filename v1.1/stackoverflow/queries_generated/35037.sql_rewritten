-- {"query": "35037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 722} 
WITH
TopActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS TotalPosts, SUM(p.Score) AS TotalScore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1000 AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) FILTER (WHERE b.Class = 1) AS Gold,
           COUNT(*) FILTER (WHERE b.Class = 2) AS Silver,
           COUNT(*) FILTER (WHERE b.Class = 3) AS Bronze,
           MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserVotesSummary AS (
    SELECT u.Id AS UserId,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCast
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
UserCommentsAverage AS (
    SELECT u.Id AS UserId,
           AVG(c.Score) AS AvgCommentScore,
           COUNT(c.Id) AS CommentCount
    FROM Users u
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
UserBestPost AS (
    SELECT p.OwnerUserId, p.Id AS PostId, p.Score, p.ViewCount, p.Title
    FROM (
        SELECT p.*, ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
    ) p
    WHERE p.rn = 1
)
SELECT 
    tau.Id AS UserId,
    tau.DisplayName,
    tau.Reputation,
    tau.TotalPosts,
    tau.TotalScore,
    COALESCE(ub.Gold,0) AS GoldBadges,
    COALESCE(ub.Silver,0) AS SilverBadges,
    COALESCE(ub.Bronze,0) AS BronzeBadges,
    COALESCE(ub.LastBadgeDate, NULL) AS LastBadgeReceived,
    COALESCE(uv.UpVotesCast,0) AS UpVotesCast,
    COALESCE(uv.DownVotesCast,0) AS DownVotesCast,
    COALESCE(uca.AvgCommentScore,0) AS AvgCommentScore,
    COALESCE(uca.CommentCount,0) AS CommentCount,
    COALESCE(ubp.PostId,NULL) AS BestPostId,
    COALESCE(ubp.Score,NULL) AS BestPostScore,
    COALESCE(ubp.ViewCount,NULL) AS BestPostViewCount,
    COALESCE(ubp.Title, NULL) AS BestPostTitle
FROM TopActiveUsers tau
LEFT JOIN UserBadges ub ON ub.UserId = tau.Id
LEFT JOIN UserVotesSummary uv ON uv.UserId = tau.Id
LEFT JOIN UserCommentsAverage uca ON uca.UserId = tau.Id
LEFT JOIN UserBestPost ubp ON ubp.OwnerUserId = tau.Id
ORDER BY tau.TotalScore DESC, tau.TotalPosts DESC
LIMIT 50;