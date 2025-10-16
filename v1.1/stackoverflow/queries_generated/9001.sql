-- {"query": "9001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3324} 

WITH TagExploded AS (
    SELECT
        p.Id AS PostId,
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        ) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
RecentAnswers AS (
    SELECT
        a.Id           AS AnswerId,
        a.ParentId     AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        te.Tag
    FROM Posts a
    JOIN TagExploded te
      ON te.PostId = a.ParentId
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= current_date - INTERVAL '30 days'
),
UserTagStats AS (
    SELECT
        OwnerUserId,
        Tag,
        COUNT(*)    AS AnswerCount,
        AVG(Score)  AS AvgScore
    FROM RecentAnswers
    GROUP BY OwnerUserId, Tag
),
GlobalTagStats AS (
    SELECT
        Tag,
        COUNT(*)    AS GlobalAnswerCount,
        AVG(Score)  AS GlobalAvgScore
    FROM RecentAnswers
    GROUP BY Tag
),
Combined AS (
    SELECT
        uts.OwnerUserId,
        uts.Tag,
        uts.AnswerCount,
        uts.AvgScore,
        gts.GlobalAnswerCount,
        gts.GlobalAvgScore,
        uts.AvgScore - gts.GlobalAvgScore AS ScoreDiff,
        ROW_NUMBER() OVER (
            PARTITION BY uts.Tag
            ORDER BY uts.AvgScore DESC
        ) AS RankInTag
    FROM UserTagStats uts
    FULL OUTER JOIN GlobalTagStats gts
      ON uts.Tag = gts.Tag
)
SELECT
    u.Id,
    u.DisplayName,
    c.Tag,
    COALESCE(c.AnswerCount,        0) AS UserAnswers,
    COALESCE(c.GlobalAnswerCount,  0) AS TotalAnswers,
    ROUND(c.AvgScore::numeric,     2) AS UserAvg,
    ROUND(c.GlobalAvgScore::numeric,2) AS GlobalAvg,
    ROUND(c.ScoreDiff::numeric,    2) AS Diff,
    c.RankInTag,
    age(current_timestamp, u.CreationDate) AS MemberSince
FROM Combined c
JOIN Users u
  ON u.Id = c.OwnerUserId
WHERE COALESCE(c.AnswerCount,       0) > 2
  AND COALESCE(c.GlobalAnswerCount, 0) > 5
ORDER BY Diff DESC, c.Tag
LIMIT 100

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    'GrandTotal' AS Tag,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS UserAnswers,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.PostTypeId = 2) AS TotalAnswers,
    ROUND(AVG(p.Score)::numeric, 2) AS UserAvg,
    (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.PostTypeId = 2) AS GlobalAvg,
    NULL::numeric AS Diff,
    NULL::int     AS RankInTag,
    age(current_timestamp, u.CreationDate) AS MemberSince
FROM Users u
LEFT JOIN Posts p
  ON p.OwnerUserId = u.Id
GROUP BY u.Id, u.DisplayName, u.CreationDate
HAVING COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) > 5
ORDER BY Tag, UserAvg DESC
;
