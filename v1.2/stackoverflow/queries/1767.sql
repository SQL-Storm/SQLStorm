WITH QuestionAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerAuthorId,
        u.DisplayName AS AnswerAuthorName,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank
    FROM 
        Posts q
        LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
        LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE 
        q.PostTypeId = 1
        AND q.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 YEAR')
), HighScoreQHosts AS (
    SELECT 
        us.Id AS UserId,
        us.DisplayName,
        COUNT(DISTINCT qa.QuestionId) AS HighScoreAnswerCount,
        AVG(qa.AnswerScore) AS AverageHighAnswerScore
    FROM 
        Users us
        INNER JOIN QuestionAnswers qa ON us.Id = qa.AnswerAuthorId
    WHERE 
        qa.AnswerRank = 1 
        AND qa.AnswerScore > 10
        AND us.Reputation > 1000
    GROUP BY 
        us.Id, us.DisplayName
), PostWithDistances AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.LastEditorUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        COALESCE(t.Id, 0) AS TagId,
        COALESCE(t.TagName, 'Untagged') AS PrimaryTag
    FROM Posts p
    LEFT JOIN (
        SELECT Id, TagName FROM Tags
    ) t ON t.Id = (
        SELECT tt.Id FROM Tags tt
        WHERE tt.TagName = (SELECT split_part(coalesce(p.Title, ''), ',', 1))
        LIMIT 1
    )
)
SELECT
    h.UserId,
    h.DisplayName,
    h.HighScoreAnswerCount,
    h.AverageHighAnswerScore,
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.PrimaryTag,
    p.CreationDate,
    p.Score
FROM HighScoreQHosts h
LEFT JOIN PostWithDistances p ON p.OwnerUserId = h.UserId
GROUP BY
    h.UserId,
    h.DisplayName,
    h.HighScoreAnswerCount,
    h.AverageHighAnswerScore,
    p.Id,
    p.Title,
    p.PrimaryTag,
    p.CreationDate,
    p.Score;