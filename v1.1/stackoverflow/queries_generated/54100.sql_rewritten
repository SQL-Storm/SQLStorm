-- {"query": "54100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2153} 
WITH RecentQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.LastActivityDate,
        ph.CreationDate AS LastEditDate
    FROM Posts p
    LEFT JOIN (
        SELECT ph.PostId,
               MAX(ph.CreationDate) AS CreationDate
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (4, 5)  -- edit title or body
        GROUP BY ph.PostId
    ) ph ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
),
AnswerMetrics AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        SUM(CASE WHEN a.Score > 0 THEN a.Score ELSE 0 END) AS PosScoreSum,
        SUM(CASE WHEN a.Score < 0 THEN a.Score ELSE 0 END) AS NegScoreSum,
        AVG(a.Score) AS AvgAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
OwnerReputation AS (
    SELECT
        u.Id,
        u.Reputation
    FROM Users u
)
SELECT
    q.Id                      AS QuestionId,
    q.OwnerUserId,
    ur.Reputation             AS OwnerReputation,
    q.Score                   AS QuestionScore,
    q.ViewCount,
    q.AnswerCount             AS RawAnswerCount,
    am.TotalAnswers,
    am.AvgAnswerScore,
    am.PosScoreSum,
    am.NegScoreSum,
    q.Tags,
    q.LastActivityDate,
    q.LastEditDate,
    (EXTRACT(epoch FROM (cast('2024-10-01 12:34:56' as timestamp) - q.CreationDate))/3600)::int AS HoursSinceCreation,
    (EXTRACT(epoch FROM (cast('2024-10-01 12:34:56' as timestamp) - q.LastActivityDate))/3600)::int AS HoursSinceLastActivity
FROM RecentQuestions q
LEFT JOIN AnswerMetrics am
       ON am.QuestionId = q.Id
LEFT JOIN OwnerReputation ur
       ON ur.Id = q.OwnerUserId
ORDER BY
    q.Score DESC NULLS LAST,
    am.AvgAnswerScore DESC NULLS LAST,
    q.ViewCount DESC
LIMIT 200;