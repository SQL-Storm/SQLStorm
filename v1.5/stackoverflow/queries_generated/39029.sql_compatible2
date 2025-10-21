WITH RecentQs AS (
    SELECT
        q.Id,
        q.CreationDate,
        unnest(string_to_array(substring(q.Tags FROM 2 FOR char_length(q.Tags) - 2), '><')) AS Tag
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= cast('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
FirstAnswerTimes AS (
    SELECT
        rq.Id       AS QuestionId,
        rq.Tag,
        MIN(a.CreationDate - rq.CreationDate) AS AnswerDelay
    FROM RecentQs rq
    JOIN Posts a
      ON a.ParentId = rq.Id
     AND a.PostTypeId = 2
    GROUP BY rq.Id, rq.Tag
),
TagStats AS (
    SELECT
        Tag,
        COUNT(DISTINCT QuestionId)                              AS QuestionCount,
        AVG(EXTRACT(EPOCH FROM AnswerDelay))                    AS AvgAnswerSeconds,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM AnswerDelay)) AS P95AnswerSeconds
    FROM FirstAnswerTimes
    GROUP BY Tag
),
AnswerCounts AS (
    SELECT
        unnest(string_to_array(substring(q.Tags FROM 2 FOR char_length(q.Tags) - 2), '><')) AS Tag,
        a.OwnerUserId,
        COUNT(*)                                                      AS AnswerCount
    FROM Posts a
    JOIN Posts q
      ON a.ParentId = q.Id
     AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= cast('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY Tag, a.OwnerUserId
),
TopAnswerers AS (
    SELECT
        ac.Tag,
        ac.OwnerUserId,
        ac.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY ac.Tag ORDER BY ac.AnswerCount DESC) AS rn
    FROM AnswerCounts ac
)
SELECT
    ts.Tag,
    ts.QuestionCount,
    CAST(ts.AvgAnswerSeconds / 3600.0 AS numeric(18, 6)) AS AvgAnswerHours,
    CAST(ts.P95AnswerSeconds / 3600.0 AS numeric(18, 6)) AS P95AnswerHours,
    u.DisplayName                         AS TopAnswerer,
    ta.AnswerCount                        AS TopAnswerCount
FROM TagStats ts
LEFT JOIN TopAnswerers ta
  ON ta.Tag = ts.Tag
 AND ta.rn = 1
LEFT JOIN Users u
  ON u.Id = ta.OwnerUserId
ORDER BY ts.QuestionCount DESC
LIMIT 10;