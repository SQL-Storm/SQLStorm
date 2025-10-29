-- {"query": "4493.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 998} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > '2023-01-01'
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    GROUP BY OwnerUserId
),
UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(upc.TotalPosts, 0) AS UserTotalPosts,
        COALESCE(upc.QuestionCount, 0) AS UserQuestionCount,
        COALESCE(upc.AnswerCount, 0) AS UserAnswerCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
    WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL)
),
RecentTopQuestions AS (
    SELECT
        Id AS QuestionId,
        Title,
        OwnerUserId,
        Score,
        AnswerCount,
        FavoriteCount,
        ROW_NUMBER() OVER (ORDER BY Score DESC, FavoriteCount DESC) AS q_rank
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate > DATE('now', '-30 days') AND AnswerCount > 0
),
AggregatedComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate > DATE('now', '-7 days')
    GROUP BY c.PostId
)
SELECT
    rtq.QuestionId,
    rtq.Title AS QuestionTitle,
    uc.DisplayName AS QuestionOwnerDisplayName,
    uc.UserTotalPosts,
    uc.UserQuestionCount,
    uc.GoldBadges,
    COALESCE(ac.CommentCount, 0) AS RecentCommentCount,
    COALESCE(ac.AvgCommentScore, 0.0) AS AvgRecentCommentScore,
    CASE
        WHEN rtq.Score > 500 THEN 'High Score'
        WHEN rtq.Score BETWEEN 100 AND 500 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    CASE
        WHEN rtq.AnswerCount > 10 THEN 'Many Answers'
        WHEN rtq.AnswerCount BETWEEN 5 AND 10 THEN 'Some Answers'
        ELSE 'Few Answers'
    END AS AnswerCategory,
    rtq.Score AS QuestionScore,
    rtq.FavoriteCount,
    rp.PostTypeName AS LatestPostType,
    rp.PostCreationDate AS LatestPostCreationDate,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rtq.QuestionId AND pl.LinkTypeId = 3) AS DuplicateLinks
FROM RecentTopQuestions rtq
JOIN UserContribution uc ON rtq.OwnerUserId = uc.UserId
LEFT JOIN AggregatedComments ac ON rtq.QuestionId = ac.PostId
LEFT JOIN RankedPosts rp ON rtq.QuestionId = rp.PostId AND rp.rn = 1
WHERE rtq.q_rank <= 20
ORDER BY rtq.q_rank;
