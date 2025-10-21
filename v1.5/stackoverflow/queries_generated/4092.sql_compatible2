WITH RECURSIVE TagHierarchy AS (
    SELECT p.Id AS PostId, t.Id AS TagId, t.TagName, 1 AS Level, p.Tags
    FROM Posts AS p
    JOIN Tags AS t ON POSITION('<' || t.TagName || '>' IN COALESCE(p.Tags, '')) > 0
    WHERE p.PostTypeId = 1
    UNION ALL
    SELECT pl.RelatedPostId AS PostId, t.Id, t.TagName, r.Level + 1, p.Tags
    FROM PostLinks AS pl
    JOIN TagHierarchy AS r ON pl.PostId = r.PostId AND pl.LinkTypeId = 3
    JOIN Posts AS p ON pl.RelatedPostId = p.Id
    JOIN Tags AS t ON POSITION('<' || t.TagName || '>' IN COALESCE(p.Tags, '')) > 0
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyGiven
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    LEFT JOIN Votes AS v ON v.UserId = u.Id AND v.VoteTypeId = 8
    GROUP BY u.Id, u.DisplayName
),
PostScoreRankings AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId, p.PostTypeId) AS PostCountByUserType,
        COALESCE(p.ViewCount, 0) AS Views,
        p.Tags,
        p.AcceptedAnswerId
    FROM Posts AS p
    WHERE p.PostTypeId IN (1, 2)
),
MaxCommentScoresPerPost AS (
    SELECT PostId, MAX(Score) AS MaxCommentScore
    FROM Comments
    GROUP BY PostId
),
AcceptedAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreated,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreated,
        u.DisplayName AS AnswerAuthor,
        CASE WHEN a.Score > 0 THEN 'Positive' ELSE 'Non-positive' END AS AnswerScoreCategory
    FROM Posts AS q
    LEFT JOIN Posts AS a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Users AS u ON a.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
),
UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        MAX(p.LastActivityDate) AS LastActivity
    FROM Users AS u
    LEFT JOIN Posts AS p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostsWithComplexTagCalculations AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'), 1) AS TagCount,
        POSITION(LOWER('sql') IN LOWER(COALESCE(p.Body, ''))) AS PositionSqlKeyword,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts AS p
    WHERE p.PostTypeId = 1
),
TopUsersPerTag AS (
    SELECT
        tag.TagName,
        u.DisplayName,
        COUNT(p.Id) AS PostsWithTag,
        SUM(p.Score) AS TotalScore,
        RANK() OVER (PARTITION BY tag.TagName ORDER BY SUM(p.Score) DESC) AS UserRankForTag
    FROM Posts AS p
    JOIN Tags AS tag ON POSITION('<' || tag.TagName || '>' IN COALESCE(p.Tags, '')) > 0
    JOIN Users AS u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY tag.TagName, u.DisplayName
)
SELECT
    p.Id AS QuestionId,
    p.Title,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.Score,
    p.ViewCount,
    p.TagCount,
    p.PositionSqlKeyword,
    p.IsClosed,
    ABS(COALESCE(ms.MaxCommentScore, 0)) AS MaxCommentAbsoluteScore,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TotalBountyGiven,
    ua.TotalPosts, ua.TotalQuestions, ua.TotalAnswers, ua.TotalComments, ua.AvgQuestionScore, ua.AvgAnswerScore,
    aa.AnswerId AS AcceptedAnswerId,
    aa.AnswerScore,
    aa.AnswerAuthor,
    aa.AnswerScoreCategory,
    STRING_AGG(DISTINCT rth.TagName, ', ') AS RecursiveDuplicateTags,
    COUNT(DISTINCT pl.Id) AS DuplicateLinkCount,
    COUNT(DISTINCT linkage.Id) AS LinkedQuestionsCount
FROM PostsWithComplexTagCalculations p
LEFT JOIN UserBadgeStats ub ON ub.UserId = p.OwnerUserId
LEFT JOIN UserActivity ua ON ua.Id = p.OwnerUserId
LEFT JOIN AcceptedAnswerStats aa ON aa.QuestionId = p.Id
LEFT JOIN MaxCommentScoresPerPost ms ON ms.PostId = p.Id
LEFT JOIN TagHierarchy rth ON rth.PostId = p.Id AND rth.Level <= 3
LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
LEFT JOIN PostLinks linkage ON linkage.PostId = p.Id AND linkage.LinkTypeId = 1
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.Score > 0
GROUP BY
    p.Id, p.Title, p.OwnerUserId, u.DisplayName, p.Score, p.ViewCount, p.TagCount, p.PositionSqlKeyword,
    p.IsClosed, ms.MaxCommentScore, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TotalBountyGiven,
    ua.TotalPosts, ua.TotalQuestions, ua.TotalAnswers, ua.TotalComments, ua.AvgQuestionScore, ua.AvgAnswerScore,
    aa.AnswerId, aa.AnswerScore, aa.AnswerAuthor, aa.AnswerScoreCategory
HAVING COUNT(DISTINCT pl.Id) > 0
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 50;