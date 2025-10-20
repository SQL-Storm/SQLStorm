WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id > 0
    GROUP BY u.Id
),
TopQuestions AS (
    SELECT
        Id,
        OwnerUserId,
        Score,
        AnswerCount,
        CommentCount,
        CreationDate,
        PostTypeId
    FROM RankedPosts
    WHERE rn <= 100
),
TopAnswers AS (
    SELECT
        Id,
        OwnerUserId,
        Score,
        CreationDate,
        PostTypeId
    FROM RankedPosts
    WHERE rn <= 100 AND PostTypeId = 2
)
SELECT
    'Top Questions Performance' AS Metric,
    COUNT(tq.Id) AS NumberOfPosts,
    AVG(tq.Score) AS AverageScore,
    AVG(tq.AnswerCount) AS AverageAnswers,
    AVG(tq.CommentCount) AS AverageComments,
    AVG((EXTRACT(EPOCH FROM TIMESTAMP '2024-10-01 12:34:56') - EXTRACT(EPOCH FROM CAST(tq.CreationDate AS TIMESTAMP))) / 86400.0) AS AverageAgeInDays
FROM TopQuestions tq
UNION ALL
SELECT
    'Top Answers Performance' AS Metric,
    COUNT(ta.Id) AS NumberOfPosts,
    AVG(ta.Score) AS AverageScore,
    CAST(NULL AS NUMERIC) AS AverageAnswers,
    CAST(NULL AS NUMERIC) AS AverageComments,
    AVG((EXTRACT(EPOCH FROM TIMESTAMP '2024-10-01 12:34:56') - EXTRACT(EPOCH FROM CAST(ta.CreationDate AS TIMESTAMP))) / 86400.0) AS AverageAgeInDays
FROM TopAnswers ta
UNION ALL
SELECT
    'Active Users Performance' AS Metric,
    COUNT(ua.UserId) AS NumberOfPosts,
    AVG(ua.TotalScore) AS AverageScore,
    AVG(ua.AnswerCount) AS AverageAnswers,
    CAST(NULL AS NUMERIC) AS AverageComments,
    AVG((EXTRACT(EPOCH FROM TIMESTAMP '2024-10-01 12:34:56') - EXTRACT(EPOCH FROM CAST(ua.LastPostDate AS TIMESTAMP))) / 86400.0) AS AverageAgeInDays
FROM UserActivity ua
WHERE ua.QuestionCount > 0 OR ua.AnswerCount > 0;