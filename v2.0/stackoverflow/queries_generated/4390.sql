-- {"query": "4390.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1926} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextPostScore,
        AVG(CAST(p.Score AS DECIMAL(10, 2))) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForType,
        SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS TotalViewCountForType
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
AnswerMetrics AS (
    SELECT
        pa.Id AS AnswerId,
        pa.ParentId AS QuestionId,
        COUNT(c.Id) AS CommentCountOnAnswer,
        SUM(CAST(c.Score AS INT)) AS TotalScoreForAnswerComments,
        ROW_NUMBER() OVER (PARTITION BY pa.ParentId ORDER BY pa.Score DESC) AS AnswerRankForQuestion
    FROM Posts AS pa
    LEFT JOIN Comments AS c ON pa.Id = c.PostId
    WHERE pa.PostTypeId = 2 -- Only Answers
    GROUP BY pa.Id, pa.ParentId, pa.Score
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(u.CreationDate) AS LatestUserCreationDate
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
)
SELECT
    rp_q.PostId AS QuestionId,
    rp_q.Title AS QuestionTitle,
    rp_q.OwnerDisplayName AS QuestionOwner,
    rp_q.CreationDate AS QuestionCreationDate,
    rp_q.Score AS QuestionScore,
    rp_q.ViewCount AS QuestionViewCount,
    rp_q.FavoriteCount AS QuestionFavoriteCount,
    rp_q.ClosedDate AS QuestionClosedDate,
    rp_q.rn_score AS QuestionRankByType,
    rp_q.PreviousPostScore AS QuestionPrevScore,
    rp_q.NextPostScore AS QuestionNextScore,
    rp_q.AvgScoreForType AS AvgQuestionScore,
    rp_q.TotalViewCountForType AS TotalQuestionViews,
    am.AnswerId AS BestAnswerId,
    am.CommentCountOnAnswer AS BestAnswerCommentCount,
    am.TotalScoreForAnswerComments AS BestAnswerTotalCommentScore,
    am.AnswerRankForQuestion AS BestAnswerRank,
    ua_q.TotalPostsOwned AS QuestionOwnerTotalPosts,
    ua_q.AnswerCount AS QuestionOwnerAnswerCount,
    ua_q.BadgeCount AS QuestionOwnerBadgeCount,
    ua_a.TotalPostsOwned AS BestAnswerOwnerTotalPosts,
    ua_a.QuestionCount AS BestAnswerOwnerQuestionCount,
    ua_a.BadgeCount AS BestAnswerOwnerBadgeCount,
    CASE
        WHEN rp_q.Score > rp_q.TotalViewCountForType / 1000 THEN 'High Engagement'
        WHEN rp_q.Score < rp_q.PreviousPostScore AND rp_q.Score < rp_q.NextPostScore THEN 'Declining Score'
        WHEN rp_q.FavoriteCount > 0 AND rp_q.AnswerCount > rp_q.FavoriteCount * 2 THEN 'Popular but Unanswered'
        ELSE 'Standard'
    END AS QuestionPerformanceCategory,
    COALESCE(rp_q.Tags, 'No Tags') AS ProcessedTags,
    UPPER(SUBSTRING(COALESCE(rp_q.OwnerDisplayName, 'Anonymous'), 1, 3)) AS OwnerInitials,
    rp_q.CreationDate >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) AS IsRecent
FROM RankedPosts AS rp_q
LEFT JOIN AnswerMetrics AS am ON rp_q.Id = am.QuestionId AND am.AnswerRankForQuestion = 1
LEFT JOIN UserActivity AS ua_q ON rp_q.OwnerUserId = ua_q.UserId
LEFT JOIN UserActivity AS ua_a ON am.AnswerId = (SELECT OwnerUserId FROM Posts WHERE Id = am.AnswerId)
WHERE rp_q.PostTypeId = 1 -- Questions
AND rp_q.Score > 0
AND rp_q.CreationDate > '2023-01-01'
AND rp_q.OwnerUserId IS NOT NULL
AND rp_q.OwnerUserId != -1
UNION ALL
SELECT
    NULL AS QuestionId,
    NULL AS QuestionTitle,
    NULL AS QuestionOwner,
    NULL AS QuestionCreationDate,
    NULL AS QuestionScore,
    NULL AS QuestionViewCount,
    NULL AS QuestionFavoriteCount,
    NULL AS QuestionClosedDate,
    NULL AS QuestionRankByType,
    NULL AS QuestionPrevScore,
    NULL AS QuestionNextScore,
    NULL AS AvgQuestionScore,
    NULL AS TotalQuestionViews,
    rp_a.Id AS AnswerId,
    COUNT(c.Id) AS BestAnswerCommentCount,
    SUM(CAST(c.Score AS INT)) AS BestAnswerTotalCommentScore,
    ROW_NUMBER() OVER (PARTITION BY rp_a.ParentId ORDER BY rp_a.Score DESC) AS BestAnswerRank,
    ua_q.TotalPostsOwned AS QuestionOwnerTotalPosts,
    ua_q.AnswerCount AS QuestionOwnerAnswerCount,
    ua_q.BadgeCount AS QuestionOwnerBadgeCount,
    ua_a.TotalPostsOwned AS BestAnswerOwnerTotalPosts,
    ua_a.QuestionCount AS BestAnswerOwnerQuestionCount,
    ua_a.BadgeCount AS BestAnswerOwnerBadgeCount,
    CASE
        WHEN rp_a.Score > 5 THEN 'Highly Rated Answer'
        WHEN rp_a.Score < 0 THEN 'Negatively Scored Answer'
        ELSE 'Standard Answer'
    END AS QuestionPerformanceCategory,
    COALESCE(rp_a.Body, 'No Body') AS ProcessedTags,
    UPPER(SUBSTRING(COALESCE(rp_a.OwnerDisplayName, 'Anonymous'), 1, 3)) AS OwnerInitials,
    rp_a.CreationDate >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) AS IsRecent
FROM RankedPosts AS rp_a
LEFT JOIN Comments AS c ON rp_a.Id = c.PostId
LEFT JOIN UserActivity AS ua_q ON rp_a.OwnerUserId = ua_q.UserId
LEFT JOIN UserActivity AS ua_a ON rp_a.OwnerUserId = ua_a.UserId
WHERE rp_a.PostTypeId = 2 -- Answers
AND rp_a.ParentId IS NOT NULL
AND rp_a.Score > 0
AND rp_a.CreationDate > '2023-01-01'
GROUP BY rp_a.Id, rp_a.ParentId, rp_a.Score, rp_a.OwnerUserId, rp_a.OwnerDisplayName, rp_a.CreationDate, rp_a.Body, rp_q.TotalViewCountForType, rp_q.Score
HAVING COUNT(c.Id) > 0 OR SUM(CAST(c.Score AS INT)) > 0
ORDER BY QuestionId NULLS FIRST, BestAnswerRank;
