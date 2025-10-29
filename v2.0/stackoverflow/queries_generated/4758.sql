-- {"query": "4758.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 888} 
WITH QuestionDetails AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.Score AS QuestionScore,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = p.Id AND c.Score > 5
        ) AS HighScoringCommentCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate ASC) AS ScoreRank,
        AVG(CAST(p.Score AS NUMERIC)) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForPostType
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2023-01-01'
),
AnswerDetails AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
UserActivity AS (
    SELECT
        UserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY UserId
)
SELECT
    qd.QuestionId,
    qd.QuestionTitle,
    qd.OwnerDisplayName,
    qd.QuestionScore,
    qd.AnswerCount,
    qd.HighScoringCommentCount,
    ad.AnswerId,
    ad.AnswerScore,
    ad.AnswerCreationDate,
    ua.TotalPosts AS OwnerTotalPosts,
    ua.QuestionCount AS OwnerQuestionCount,
    ua.AnswerCount AS OwnerAnswerCount,
    CASE
        WHEN qd.ScoreRank = 1 THEN 'Top Scored Question'
        WHEN qd.ScoreRank <= 10 THEN 'High Scored Question'
        ELSE 'Regular Question'
    END AS QuestionCategory,
    CASE
        WHEN ad.AnswerRank = 1 AND ad.AnswerScore > qd.AvgScoreForPostType THEN 'Best Answer'
        WHEN ad.AnswerRank <= 5 THEN 'Top Answer'
        ELSE 'Other Answer'
    END AS AnswerCategory,
    CASE
        WHEN qd.QuestionTitle LIKE '%[a-z]%' THEN 'Contains Letters'
        ELSE 'No Letters'
    END AS TitleFormat,
    CASE
        WHEN qd.OwnerDisplayName IS NULL OR qd.OwnerDisplayName = '' THEN 'Anonymous Owner'
        WHEN LENGTH(qd.OwnerDisplayName) > 15 THEN 'Long Display Name'
        ELSE 'Standard Display Name'
    END AS OwnerNameDescriptor
FROM QuestionDetails qd
LEFT JOIN AnswerDetails ad ON qd.QuestionId = ad.QuestionId
LEFT JOIN UserActivity ua ON qd.OwnerUserId = ua.UserId
WHERE qd.QuestionScore > 100
UNION ALL
SELECT
    NULL,
    'Total Questions',
    NULL,
    CAST(COUNT(qd.QuestionId) AS VARCHAR(50)),
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM QuestionDetails qd
WHERE qd.QuestionScore > 100
GROUP BY qd.QuestionId -- This grouping is effectively for the UNION ALL to aggregate
HAVING COUNT(qd.QuestionId) > 0;