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
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - qa.QuestionCreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = qa.QuestionId AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = qa.QuestionId AND v.VoteTypeId = 3) AS DownVoteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qa.QuestionId) AS CommentCount,
        COALESCE((SELECT SUM(Score) FROM Comments c WHERE c.PostId = qa.QuestionId), 0) AS TotalCommentScore,
        CASE
            WHEN qa.LatestAnswerDate IS NOT NULL
            THEN CAST(EXTRACT(EPOCH FROM (qa.LatestAnswerDate - qa.QuestionCreationDate)) / 60 AS INTEGER)
            ELSE NULL
        END AS TimeToFirstAnswerMinutes
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
    CAST(qs.UpVoteCount AS DOUBLE PRECISION) / NULLIF(qs.AnswerCount, 0) AS UpvotesPerAnswer,
    CASE WHEN qs.DaysSinceCreation > 0 THEN CAST((qs.UpVoteCount + qs.DownVoteCount) AS DOUBLE PRECISION) / qs.DaysSinceCreation ELSE (qs.UpVoteCount + qs.DownVoteCount) END AS ScorePerDay,
    p.Score
FROM
    QuestionStats qs
JOIN
    Posts p ON qs.QuestionId = p.Id
GROUP BY
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
    (qs.UpVoteCount + qs.DownVoteCount),
    UpvotesPerAnswer,
    ScorePerDay,
    p.Score
ORDER BY
    p.Score DESC,
    qs.UpVoteCount DESC,
    qs.AnswerCount DESC
LIMIT 1000;