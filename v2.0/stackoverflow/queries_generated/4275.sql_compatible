WITH RECURSIVE UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT SUM(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RowNum
    FROM Users u
    WHERE u.Id > 0
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE WHEN p.PostTypeId = 1 THEN COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2), 0) ELSE 0 END AS UpVoteCount,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCountForPost,
        COALESCE((SELECT AVG(CAST(c.Score AS NUMERIC)) FROM Comments c WHERE c.PostId = p.Id), 0) AS AvgCommentScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
RankedPosts AS (
    SELECT
        pe.PostId,
        pe.OwnerUserId,
        pe.Title,
        pe.PostScore,
        pe.AnswerCount,
        pe.CommentCountForPost,
        pe.UpVoteCount,
        pe.AvgCommentScore,
        pe.PostCreationDate,
        ROW_NUMBER() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostScore DESC, pe.PostCreationDate DESC) AS UserPostRank,
        NTILE(5) OVER (ORDER BY pe.PostScore DESC) AS ScoreQuintile
    FROM PostEngagement pe
),
UserPostPerformance AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.BadgeCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalScore,
        ua.RowNum,
        rp.UserPostRank,
        rp.ScoreQuintile,
        rp.PostId AS TopPostId,
        rp.Title AS TopPostTitle,
        rp.PostScore AS TopPostScore,
        rp.AnswerCount AS TopPostAnswerCount,
        rp.CommentCountForPost AS TopPostCommentCount,
        rp.UpVoteCount AS TopPostUpVoteCount,
        rp.AvgCommentScore AS TopPostAvgCommentScore,
        rp.PostCreationDate AS TopPostCreationDate
    FROM UserActivity ua
    LEFT JOIN RankedPosts rp ON ua.UserId = rp.OwnerUserId AND rp.UserPostRank = 1
    WHERE ua.RowNum <= 500
)
SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.BadgeCount,
    up.QuestionCount,
    up.AnswerCount,
    up.TotalScore,
    up.UserPostRank,
    up.ScoreQuintile,
    up.TopPostTitle,
    up.TopPostScore,
    up.TopPostAnswerCount,
    up.TopPostCommentCount,
    up.TopPostUpVoteCount,
    up.TopPostAvgCommentScore,
    up.TopPostCreationDate,
    ua_prev.DisplayName AS PreviousUserDisplayName,
    ua_prev.Reputation AS PreviousUserReputation,
    COALESCE(up.TopPostScore, 0) + COALESCE(up.TopPostAnswerCount, 0) * 5 AS WeightedScore,
    CASE
        WHEN up.TopPostScore > 100 THEN 'HighScore'
        WHEN up.TopPostScore > 10 THEN 'MidScore'
        ELSE 'LowScore'
    END AS ScoreCategory,
    CASE
        WHEN up.TopPostCreationDate BETWEEN DATE_TRUNC('year', CAST('2024-10-01' AS DATE)) AND CAST('2024-10-01' AS DATE) THEN 'CurrentYear'
        ELSE 'PreviousYears'
    END AS PostAgeCategory
FROM UserPostPerformance up
LEFT JOIN UserActivity ua_prev
    ON ua_prev.RowNum = up.RowNum + 1
WHERE up.Reputation > 10000
ORDER BY up.Reputation DESC, up.UserId
LIMIT 100;