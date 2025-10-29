-- {"query": "4395.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 826}
WITH LatestPostEdits AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.LastEditDate,
        ROW_NUMBER() OVER(PARTITION BY p.Id ORDER BY p.LastEditDate DESC) as rn
    FROM Posts p
    WHERE p.LastEditDate IS NOT NULL
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN pt.Name = 'Question' THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN pt.Name = 'Answer' THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN pt.Name = 'Question' THEN p.Score END) AS AvgQuestionScore,
        MAX(CASE WHEN pt.Name = 'Question' THEN p.ViewCount ELSE 0 END) AS MaxQuestionViewCount,
        SUM(p.CommentCount) AS TotalCommentCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY u.Id, u.DisplayName
),
HighReputationUsers AS (
    SELECT
        Id,
        DisplayName,
        Reputation
    FROM Users
    WHERE Reputation > 100000
),
FrequentVoters AS (
    SELECT
        UserId,
        COUNT(*) AS VoteCount,
        RANK() OVER (ORDER BY COUNT(*) DESC) as rnk
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY UserId
    HAVING COUNT(*) > 5000
),
PostsWithRecentEdits AS (
    SELECT
        lp.PostId,
        lp.Title,
        lp.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        lp.LastEditDate,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - lp.LastEditDate)) / 60 AS INTEGER) AS MinutesSinceLastEdit
    FROM LatestPostEdits lp
    JOIN Users u ON lp.OwnerUserId = u.Id
    WHERE lp.rn = 1
      AND lp.LastEditDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
)
SELECT
    hr.DisplayName AS HighRepUser,
    fv.UserId AS FrequentVoterId,
    COUNT(DISTINCT pwe.PostId) AS PostsEditedRecently,
    AVG(CAST(pwe.MinutesSinceLastEdit AS FLOAT)) AS AvgMinutesSinceEdit,
    SUM(CASE WHEN pwe.Title LIKE '%SQL%' OR pwe.Title LIKE '%performance%' THEN 1 ELSE 0 END) AS PostsWithKeywords,
    MAX(COALESCE(ups.QuestionCount, 0)) AS MaxUserQuestions,
    MIN(COALESCE(ups.AnswerCount, 0)) AS MinUserAnswers,
    SUM(COALESCE(ups.TotalCommentCount, 0)) AS TotalCommentsByUsers
FROM HighReputationUsers hr
FULL OUTER JOIN FrequentVoters fv ON hr.Id = fv.UserId
LEFT JOIN PostsWithRecentEdits pwe ON hr.Id = pwe.OwnerUserId OR fv.UserId = pwe.OwnerUserId
LEFT JOIN UserPostStats ups ON ups.UserId = COALESCE(pwe.OwnerUserId, hr.Id, fv.UserId)
WHERE hr.DisplayName IS NOT NULL OR fv.UserId IS NOT NULL
GROUP BY hr.DisplayName, fv.UserId
HAVING COUNT(DISTINCT pwe.PostId) > 10
ORDER BY AvgMinutesSinceEdit DESC, PostsWithKeywords DESC;