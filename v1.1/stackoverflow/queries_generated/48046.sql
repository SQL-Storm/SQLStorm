-- {"query": "48046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 616} 

WITH QuestionAnswers AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.CreationDate AS QuestionCreationDate,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerDate
    FROM
        Posts p
    LEFT JOIN
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id, p.Title, p.CreationDate
),
QuestionStats AS (
    SELECT
        qa.QuestionId,
        qa.QuestionTitle,
        qa.QuestionCreationDate,
        qa.AnswerCount,
        qa.AvgAnswerScore,
        qa.LatestAnswerDate,
        DATEDIFF(day, qa.QuestionCreationDate, GETDATE()) AS DaysSinceCreation,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = qa.QuestionId AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = qa.QuestionId AND v.VoteTypeId = 3) AS DownVoteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qa.QuestionId) AS CommentCount,
        COALESCE((SELECT SUM(Score) FROM Comments c WHERE c.PostId = qa.QuestionId), 0) AS TotalCommentScore,
        CASE WHEN qa.LatestAnswerDate IS NOT NULL THEN DATEDIFF(minute, qa.QuestionCreationDate, qa.LatestAnswerDate) ELSE NULL END AS TimeToFirstAnswerMinutes
    FROM
        QuestionAnswers qa
)
SELECT
    qs.QuestionId,
    qs.QuestionTitle,
    qs.QuestionCreationDate,
    qs.AnswerCount,
    qs.AvgAnswerScore,
    qs.DaysSinceCreation,
    qs.UpVoteCount,
    qs.DownVoteCount,
    qs.CommentCount,
    qs.TotalCommentScore,
    qs.TimeToFirstAnswerMinutes,
    (qs.UpVoteCount + qs.DownVoteCount) AS TotalVotes,
    CAST(qs.UpVoteCount AS REAL) / NULLIF(qs.AnswerCount, 0) AS UpvotesPerAnswer,
    CASE WHEN qs.DaysSinceCreation > 0 THEN CAST(qs.Score AS REAL) / qs.DaysSinceCreation ELSE qs.Score END AS ScorePerDay
FROM
    QuestionStats qs
JOIN
    Posts p ON qs.QuestionId = p.Id
ORDER BY
    qs.Score DESC, qs.UpVoteCount DESC, qs.AnswerCount DESC
LIMIT 1000;
