-- {"query": "48050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 718} 

WITH RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViews,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) AS AnswerCount,
        (SELECT AVG(Score) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) AS AvgAnswerScore,
        p.CreationDate AS QuestionCreationDate,
        (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId = 10) AS CloseVoteCount,
        (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId = 19) AS ProtectVoteCount
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1 -- Questions
        AND p.CreationDate >= DATE('now', '-30 days') -- Last 30 days
    ORDER BY
        p.Score DESC, p.ViewCount DESC
    LIMIT 100
),
QuestionEngagement AS (
    SELECT
        rq.QuestionId,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount
    FROM
        RecentQuestions rq
    LEFT JOIN
        Comments c ON rq.QuestionId = c.PostId
    LEFT JOIN
        Votes v ON rq.QuestionId = v.PostId
    GROUP BY
        rq.QuestionId
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.QuestionScore,
    rq.QuestionViews,
    rq.OwnerDisplayName,
    rq.OwnerReputation,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.QuestionCreationDate,
    qe.CommentCount,
    qe.UpVoteCount,
    qe.DownVoteCount,
    qe.FavoriteCount,
    rq.CloseVoteCount,
    rq.ProtectVoteCount,
    (rq.QuestionScore * 1.0 / NULLIF(rq.QuestionViews, 0)) AS ScoreToViewRatio,
    (qe.UpVoteCount * 1.0 / NULLIF(rq.AnswerCount, 0)) AS UpVotePerAnswerRatio,
    (rq.QuestionScore + qe.UpVoteCount * 5 - qe.DownVoteCount * 2 + qe.CommentCount * 0.5 - rq.CloseVoteCount * 10) AS CompositeScore
FROM
    RecentQuestions rq
JOIN
    QuestionEngagement qe ON rq.QuestionId = qe.QuestionId
WHERE
    rq.OwnerReputation > 1000
ORDER BY
    CompositeScore DESC
LIMIT 50;
