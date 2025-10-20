-- {"query": "35026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 649} 
WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
    ORDER BY u.Reputation DESC
    LIMIT 50
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserActivity AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS Questions,
           COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS Answers,
           COUNT(*) AS TotalPosts,
           SUM(COALESCE(p.Score, 0)) AS TotalScore,
           MAX(p.CreationDate) AS LastPostDate,
           SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
           SUM(COALESCE(p.AnswerCount,0)) AS AnswersToQuestions
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserComments AS (
    SELECT c.UserId,
           COUNT(*) AS CommentCount,
           SUM(COALESCE(c.Score, 0)) AS CommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVotes AS (
    SELECT v.UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast,
           SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesCast
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ua.Questions,
    ua.Answers,
    ua.TotalPosts,
    ua.TotalScore,
    ua.LastPostDate,
    ua.TotalViews,
    ua.AnswersToQuestions,
    uc.CommentCount,
    uc.CommentScore,
    uv.UpVotesCast,
    uv.DownVotesCast,
    uv.FavoritesCast
FROM TopUsers u
LEFT JOIN UserBadges ub ON ub.UserId = u.Id
LEFT JOIN UserActivity ua ON ua.UserId = u.Id
LEFT JOIN UserComments uc ON uc.UserId = u.Id
LEFT JOIN UserVotes uv ON uv.UserId = u.Id
ORDER BY u.Reputation DESC, ua.TotalScore DESC;