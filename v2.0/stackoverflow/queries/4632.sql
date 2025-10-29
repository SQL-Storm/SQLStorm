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
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS prev_day_score_change
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '365 days')
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(rp.PostId) AS TotalPosts,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CAST(rp.Score AS DOUBLE PRECISION)) AS AvgPostScore,
        MAX(rp.PostCreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
CommentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(CAST(c.Score AS DOUBLE PRECISION)) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '180 days')
    GROUP BY c.PostId
),
PostWithCommentMetrics AS (
    SELECT
        rp.PostId,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.PostCreationDate,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.PostTypeName,
        rp.rn_desc,
        rp.rn_asc,
        rp.avg_score_by_type,
        rp.prev_day_score_change,
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
    UPPER(SUBSTRING(p.PostTypeName FROM 1 FOR 1)) || LOWER(SUBSTRING(p.PostTypeName FROM 2 FOR 1000)) AS FormattedPostTypeName,
    CASE
        WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.PostId AND c.UserId IS NOT NULL AND c.CreationDate > p.PostCreationDate)
        ELSE 0
    END AS CommentsOnAnsweredQuestions,
    CASE
        WHEN p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts p3 WHERE p3.Id = p.PostId AND p3.Id IS NOT NULL) THEN
            (SELECT
                CASE
                    WHEN p2.OwnerUserId = p.OwnerUserId THEN 'Same Owner'
                    ELSE 'Different Owner'
                END
            FROM Posts p2
            WHERE p2.Id = (
                SELECT parent_id FROM (
                    SELECT parent.Id AS parent_id FROM Posts parent WHERE parent.Id = (
                        SELECT parent2.Id FROM Posts parent2 WHERE parent2.Id = p.PostId
                    )
                ) x
                LIMIT 1
            )
            LIMIT 1)
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