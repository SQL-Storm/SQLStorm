-- {"query": "4288.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1600}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_score_desc,
        COUNT(c.Id) OVER(PARTITION BY p.Id) AS CommentCountForPost,
        AVG(CAST(p.Score AS NUMERIC(10, 2))) OVER(PARTITION BY p.PostTypeId) AS AvgScoreForPostType,
        LAG(p.Score, 1, 0) OVER(ORDER BY p.CreationDate) AS PreviousPostScore,
        p.Title,
        p.ParentId
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2)
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        COUNT(rp.PostId) AS TotalPosts,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CAST(rp.Score AS NUMERIC(10, 2))) AS AvgUserPostScore,
        MAX(rp.PostCreationDate) AS LastPostDate
    FROM Users u
    JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS NumberOfRelatedPosts,
        STRING_AGG(lt.Name || ': ' || rpt.Name, ', ' ORDER BY lt.Name) AS LinkRelationships
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p_related ON pl.RelatedPostId = p_related.Id
    JOIN PostTypes rpt ON p_related.PostTypeId = rpt.Id
    GROUP BY pl.PostId
)
SELECT
    rp_q.PostId AS QuestionId,
    rp_q.PostTypeName AS QuestionType,
    rp_q.Title AS QuestionTitle,
    rp_q.Score AS QuestionScore,
    rp_q.ViewCount AS QuestionViews,
    rp_q.CommentCountForPost AS QuestionComments,
    COALESCE(ups_q.TotalPosts, 0) AS OwnerTotalPosts,
    COALESCE(ups_q.QuestionCount, 0) AS OwnerQuestionCount,
    COALESCE(ups_q.AvgUserPostScore, 0.0) AS OwnerAvgPostScore,
    rp_a.PostId AS AnswerId,
    rp_a.PostTypeName AS AnswerType,
    rp_a.Score AS AnswerScore,
    rp_a.CommentCountForPost AS AnswerComments,
    COALESCE(ups_a.TotalPosts, 0) AS AnswererTotalPosts,
    COALESCE(ups_a.AnswerCount, 0) AS AnswererAnswerCount,
    COALESCE(ups_a.AvgUserPostScore, 0.0) AS AnswererAvgPostScore,
    CASE
        WHEN rp_q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp_a.PostCreationDate > rp_q.PostCreationDate THEN 'Answered'
        ELSE 'No Answer'
    END AS Status,
    COALESCE(pla.NumberOfRelatedPosts, 0) AS RelatedPostsCount,
    pla.LinkRelationships,
    rp_q.rn_desc AS QuestionRankByType,
    rp_q.rn_score_desc AS QuestionRankByScore,
    rp_q.AvgScoreForPostType AS GlobalAvgQuestionScore,
    rp_q.PreviousPostScore AS ScoreOfPreviousQuestion,
    CASE WHEN rp_q.FavoriteCount > 0 THEN 'Favorited' ELSE 'Not Favorited' END AS IsFavorite,
    UPPER(SUBSTRING(rp_q.PostTypeName FROM 1 FOR 1)) || LOWER(SUBSTRING(rp_q.PostTypeName FROM 2)) AS FormattedPostType
FROM RankedPosts rp_q
LEFT JOIN RankedPosts rp_a
    ON rp_q.PostId = rp_a.ParentId AND rp_a.PostTypeId = 2
LEFT JOIN UserPostStats ups_q
    ON rp_q.OwnerUserId = ups_q.UserId
LEFT JOIN UserPostStats ups_a
    ON rp_a.OwnerUserId = ups_a.UserId
LEFT JOIN PostLinkAnalysis pla
    ON rp_q.PostId = pla.PostId
WHERE
    rp_q.PostTypeId = 1
    AND rp_q.Score > 50
    AND rp_q.ViewCount > 1000
    AND (rp_q.ClosedDate IS NULL OR rp_q.ClosedDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'))
    AND rp_q.OwnerUserId IS NOT NULL
    AND rp_q.CommentCountForPost BETWEEN 1 AND 20
    AND rp_q.PostCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
    AND rp_q.PostTypeName LIKE '%Question%'
GROUP BY
    rp_q.PostId,
    rp_q.PostTypeId,
    rp_q.OwnerUserId,
    rp_q.PostCreationDate,
    rp_q.Score,
    rp_q.ViewCount,
    rp_q.AnswerCount,
    rp_q.FavoriteCount,
    rp_q.ClosedDate,
    rp_q.Title,
    rp_q.CommentCountForPost,
    rp_q.AvgScoreForPostType,
    rp_q.PreviousPostScore,
    rp_a.PostId,
    rp_a.PostTypeName,
    rp_a.Score,
    rp_a.CommentCountForPost,
    rp_a.PostCreationDate,
    ups_q.TotalPosts,
    ups_q.QuestionCount,
    ups_q.AvgUserPostScore,
    ups_a.TotalPosts,
    ups_a.AnswerCount,
    ups_a.AvgUserPostScore,
    pla.NumberOfRelatedPosts,
    pla.LinkRelationships,
    rp_q.rn_desc,
    rp_q.rn_score_desc,
    rp_q.FavoriteCount,
    rp_q.PostTypeName
HAVING
    COUNT(rp_a.PostId) > 0 OR rp_q.AnswerCount > 0
ORDER BY
    rp_q.Score DESC, rp_q.ViewCount DESC;