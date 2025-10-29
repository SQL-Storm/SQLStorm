-- {"query": "3908.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2629}
WITH
UserAgg AS (
    SELECT
        u.Id                                      AS UserId,
        COALESCE(u.DisplayName, '[deleted]')      AS DisplayName,
        COALESCE(u.Reputation, 0)                 AS Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)   AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)   AS AnswerCount,
        SUM(CASE
                WHEN v.VoteTypeId = 2 THEN 1
                WHEN v.VoteTypeId = 3 THEN -1
                ELSE 0
            END)                                 AS VoteScore,
        COUNT(b.Id)                              AS BadgeCount,
        MAX(p.CreationDate)                      AS LastPostDate
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes   v ON v.UserId = u.Id
    LEFT JOIN Badges  b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagExplode AS (
    SELECT
        p.Id                                          AS PostId,
        unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),
TagAgg AS (
    SELECT
        te.Tag,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)                 AS QuestionCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)            AS AvgScore,
        SUM(CASE
                WHEN v.VoteTypeId = 2 THEN 1
                WHEN v.VoteTypeId = 3 THEN -1
                ELSE 0
            END)                                                AS TotalVoteDelta
    FROM TagExplode te
    JOIN Posts p   ON p.Id = te.PostId
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY te.Tag
),
UserTopTags AS (
    SELECT
        ua.UserId,
        ta.Tag,
        ROW_NUMBER() OVER (PARTITION BY ua.UserId
                           ORDER BY ta.QuestionCount DESC, ta.AvgScore DESC) AS rn
    FROM UserAgg ua
    JOIN TagExplode te ON te.PostId IN (
        SELECT Id FROM Posts WHERE OwnerUserId = ua.UserId
    )
    JOIN TagAgg ta     ON ta.Tag = te.Tag
    GROUP BY ua.UserId, ta.Tag, ta.QuestionCount, ta.AvgScore
),
RecentQuestion AS (
    SELECT
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserTagCounts AS (
    SELECT
        ua.UserId,
        (SELECT COUNT(DISTINCT te.Tag)
         FROM TagExplode te
         WHERE te.PostId IN (SELECT Id FROM Posts p2 WHERE p2.OwnerUserId = ua.UserId)
        ) AS DistinctTagCount
    FROM UserAgg ua
    GROUP BY ua.UserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.VoteScore,
    ua.BadgeCount,
    COALESCE(rq.Title, 'No Questions')               AS LatestQuestionTitle,
    COALESCE(rq.CreationDate, CAST('1970-01-01' AS TIMESTAMP)) AS LatestQuestionDate,
    CASE
        WHEN ua.QuestionCount = 0 THEN NULL
        ELSE CAST(ua.AnswerCount AS DECIMAL) / NULLIF(ua.QuestionCount,0)
    END                                            AS AnswerPerQuestionRatio,
    COALESCE(ut.Tag, 'N/A')                         AS TopTag,
    tg.QuestionCount                               AS TopTagQuestionCount,
    tg.AvgScore                                    AS TopTagAvgScore,
    utc.DistinctTagCount                           AS DistinctTagCount,
    CASE
        WHEN ua.DisplayName IS NULL THEN NULL
        ELSE CONCAT('https://stackoverflow.com/users/', ua.UserId, '/', REPLACE(LOWER(ua.DisplayName), ' ', '-'))
    END                                            AS ProfileUrl
FROM UserAgg ua
LEFT JOIN RecentQuestion rq   ON rq.OwnerUserId = ua.UserId AND rq.rn = 1
LEFT JOIN UserTopTags   ut   ON ut.UserId = ua.UserId AND ut.rn = 1
LEFT JOIN TagAgg        tg   ON tg.Tag = ut.Tag
LEFT JOIN UserTagCounts utc  ON utc.UserId = ua.UserId
WHERE ua.Reputation > 1000
  AND (ua.BadgeCount > 0 OR ua.VoteScore > 10)

UNION ALL

SELECT
    -1            AS UserId,
    'System'      AS DisplayName,
    NULL          AS Reputation,
    0             AS QuestionCount,
    0             AS AnswerCount,
    0             AS VoteScore,
    0             AS BadgeCount,
    'N/A'         AS LatestQuestionTitle,
    CAST('1970-01-01' AS TIMESTAMP) AS LatestQuestionDate,
    NULL          AS AnswerPerQuestionRatio,
    'N/A'         AS TopTag,
    0             AS TopTagQuestionCount,
    NULL          AS TopTagAvgScore,
    0             AS DistinctTagCount,
    NULL          AS ProfileUrl
ORDER BY Reputation DESC NULLS LAST, UserId;