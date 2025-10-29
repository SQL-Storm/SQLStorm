-- {"query": "4632.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1151} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ASC) AS rn_asc,
        AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS prev_day_score_change
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > DATE('now', '-365 day')
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(rp.PostId) AS TotalPosts,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CAST(rp.Score AS FLOAT)) AS AvgPostScore,
        MAX(rp.PostCreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
CommentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(CAST(c.Score AS FLOAT)) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate > DATE('now', '-180 day')
    GROUP BY c.PostId
),
PostWithCommentMetrics AS (
    SELECT
        rp.*,
        COALESCE(ca.CommentCount, 0) AS ActualCommentCount,
        COALESCE(ca.AvgCommentScore, 0) AS ActualAvgCommentScore
    FROM RankedPosts rp
    LEFT JOIN CommentAnalysis ca ON rp.PostId = ca.PostId
)
SELECT
    p.PostId,
    p.PostTypeName,
    p.PostCreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount AS PostAnswerCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    ups.TotalPosts AS OwnerTotalPosts,
    ups.QuestionCount AS OwnerQuestionCount,
    ups.AnswerCount AS OwnerAnswerCount,
    ups.AvgPostScore AS OwnerAvgPostScore,
    p.avg_score_by_type,
    p.prev_day_score_change,
    p.rn_desc,
    p.rn_asc,
    p.ActualCommentCount,
    p.ActualAvgCommentScore,
    CASE
        WHEN p.Score > 100 AND p.ViewCount > 10000 THEN 'High Engagement'
        WHEN p.Score < 0 OR p.ViewCount < 50 THEN 'Low Engagement'
        ELSE 'Medium Engagement'
    END AS EngagementLevel,
    UPPER(SUBSTRING(p.PostTypeName, 1, 1)) || LOWER(SUBSTRING(p.PostTypeName, 2)) AS FormattedPostTypeName,
    CASE
        WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.PostId AND c.UserId IS NOT NULL AND c.CreationDate > p.PostCreationDate)
        ELSE 0
    END AS CommentsOnAnsweredQuestions,
    CASE
        WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN
            (SELECT
                CASE
                    WHEN p2.OwnerUserId = p.OwnerUserId THEN 'Same Owner'
                    ELSE 'Different Owner'
                END
            FROM Posts p2 WHERE p2.Id = p.ParentId)
        ELSE 'N/A'
    END AS ParentOwnerRelationship
FROM PostWithCommentMetrics p
JOIN UserPostStats ups ON p.OwnerUserId = ups.UserId
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE
    p.rn_desc <= 100
    AND ups.Reputation > 1000
    AND p.PostTypeId IN (1, 2)
    AND p.Score > 0
    AND (p.ViewCount BETWEEN 100 AND 5000 OR p.AnswerCount > 5)
ORDER BY
    p.PostCreationDate DESC;