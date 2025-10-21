-- {"query": "39049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 1787} 

WITH
QuestionAnswerTime AS (
    SELECT
        q.Id                   AS QuestionId,
        a.Id                   AS AnswerId,
        a.OwnerUserId          AS AnswererId,
        q.CreationDate         AS QuestionDate,
        a.CreationDate         AS AnswerDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0 AS HoursToAnswer
    FROM Posts q
    JOIN Posts a
      ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1    -- questions
      AND a.PostTypeId = 2    -- answers
),
UserPerformance AS (
    SELECT
        u.Id                      AS UserId,
        u.DisplayName             AS UserName,
        COUNT(qat.AnswerId)       AS TotalAnswers,
        AVG(qat.HoursToAnswer)    AS AvgHoursToAnswer,
        SUM(CASE WHEN p.AcceptedAnswerId = qat.AnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)       AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)       AS DownVotesReceived
    FROM Users u
    LEFT JOIN QuestionAnswerTime qat
      ON qat.AnswererId = u.Id
    LEFT JOIN Posts p
      ON p.AcceptedAnswerId = qat.AnswerId
    LEFT JOIN Votes v
      ON v.PostId = qat.AnswerId
    WHERE u.CreationDate < now() - INTERVAL '30 days'
    GROUP BY u.Id, u.DisplayName
),
TagDistribution AS (
    SELECT
        t.tag        AS TagName,
        COUNT(*)     AS QuestionCount
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT unnest(
            string_to_array(
                substring(q.Tags, 2, length(q.Tags) - 2),
                '><'
            )
        ) AS tag
    ) AS t
    WHERE q.PostTypeId = 1
    GROUP BY t.tag
),
TopTags AS (
    SELECT
        TagName,
        QuestionCount,
        RANK() OVER (ORDER BY QuestionCount DESC) AS rnk
    FROM TagDistribution
),
FinalStats AS (
    SELECT
        up.UserId,
        up.UserName,
        up.TotalAnswers,
        ROUND(up.AvgHoursToAnswer, 2) AS AvgHoursToAnswer,
        up.AcceptedAnswers,
        up.UpVotesReceived,
        up.DownVotesReceived,
        tt.TagName    AS TopTag,
        tt.QuestionCount
    FROM UserPerformance up
    CROSS JOIN LATERAL (
        SELECT TagName, QuestionCount
        FROM TopTags
        WHERE rnk = 1
        LIMIT 1
    ) AS tt
)
SELECT *
FROM FinalStats
ORDER BY AcceptedAnswers DESC, TotalAnswers DESC
LIMIT 20;
