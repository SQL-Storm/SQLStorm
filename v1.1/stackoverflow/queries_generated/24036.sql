-- {"query": "24036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3202} 

WITH answers_union AS (
    SELECT p.Id AS QuestionId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND EXISTS (SELECT 1
                  FROM Posts a
                  WHERE a.ParentId = p.Id
                    AND a.PostTypeId = 2)
    UNION ALL
    SELECT p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND NOT EXISTS (SELECT 1
                      FROM Posts a
                      WHERE a.ParentId = p.Id
                        AND a.PostTypeId = 2)
),
duplicate_chain AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           0 AS depth
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    UNION ALL
    SELECT d.PostId,
           pl.RelatedPostId,
           d.depth + 1
    FROM duplicate_chain d
    JOIN PostLinks pl ON pl.PostId = d.RelatedPostId
                      AND pl.LinkTypeId = 3
),
tag_counts AS (
    SELECT q.QuestionId,
           COUNT(DISTINCT t.TagName) AS TagCount
    FROM Posts q
    JOIN answers_union au ON au.QuestionId = q.Id
    JOIN Tags t ON FIND_IN_SET(t.TagName, q.Tags) > 0
    GROUP BY q.QuestionId
),
recent_activity AS (
    SELECT p.Id AS PostId,
           p.CreationDate,
           p.Score,
           p.AnswerCount,
           COALESCE((SELECT MIN(a.CreationDate)
                     FROM Posts a
                     WHERE a.ParentId = p.Id
                       AND a.PostTypeId = 2),
                    p.CreationDate) AS FirstAnswerDate,
           p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
),
user_info AS (
    SELECT u.Id   AS UserId,
           u.Reputation
    FROM Users u
)
SELECT
    ra.PostId                    AS QuestionId,
    ra.Score                     AS QuestionScore,
    ra.AnswerCount,
    rc.TagCount,
    EXTRACT(EPOCH FROM (ra.FirstAnswerDate - ra.CreationDate))/3600
                                   AS HoursToFirstAnswer,
    u.Reputation                 AS OwnerReputation,
    (ra.AnswerCount + rc.TagCount) * 3 + u.Reputation / 10
                                   AS CompositeMetric,
    d.RelatedPostId,
    d.depth,
    ROW_NUMBER() OVER(ORDER BY
        (ra.AnswerCount + rc.TagCount) * 3 + u.Reputation / 10 DESC) AS RowNum
FROM recent_activity ra
LEFT JOIN tag_counts rc ON rc.QuestionId = ra.PostId
LEFT JOIN duplicate_chain d ON d.PostId = ra.PostId
LEFT JOIN user_info u ON u.UserId = ra.OwnerUserId
WHERE (ra.AnswerCount > 0 AND ra.Score > 0)
   OR (ra.AnswerCount = 0 AND ra.Score > 10)
ORDER BY CompositeMetric DESC
LIMIT 200;
