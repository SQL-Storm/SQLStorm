-- {"query": "3134.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2118} 

WITH
    UserReputation AS (
        SELECT
            u.Id                                 AS UserId,
            u.DisplayName,
            u.Reputation,
            RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank
        FROM Users u
    ),
    UserGoldBadge AS (
        SELECT
            b.UserId,
            MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge
        FROM Badges b
        GROUP BY b.UserId
    ),
    UserAnswerStats AS (
        SELECT
            p.OwnerUserId                      AS UserId,
            COUNT(*) FILTER (WHERE p.Score IS NOT NULL)          AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)      AS AvgAnswerScore,
            MAX(p.CreationDate)                                 AS LastAnswerDate
        FROM Posts p
        WHERE p.PostTypeId = 2                -- Answers
        GROUP BY p.OwnerUserId
    ),
    UserTagActivity AS (
        SELECT
            a.OwnerUserId                      AS UserId,
            UNNEST(string_to_array(
                     substring(q.Tags, 2, length(q.Tags)-2),
                     '><'))                     AS Tag,
            COUNT(*)                           AS TagAnswerCount,
            ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId
                               ORDER BY COUNT(*) DESC)          AS TagRank
        FROM Posts a
        JOIN Posts q ON a.ParentId = q.Id
        WHERE a.PostTypeId = 2                -- Answers
          AND q.PostTypeId = 1                -- Questions
          AND a.OwnerUserId IS NOT NULL
        GROUP BY a.OwnerUserId, Tag
    ),
    LatestPostHistory AS (
        SELECT
            ph.PostId,
            ph.PostHistoryTypeId,
            ph.CreationDate,
            ph.Comment,
            ROW_NUMBER() OVER (PARTITION BY ph.PostId
                               ORDER BY ph.CreationDate DESC) AS rn
        FROM PostHistory ph
    ),
    MedianReputation AS (
        SELECT
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Reputation) AS MedianRep
        FROM Users
    )
SELECT
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.RepRank,
    COALESCE(ug.HasGoldBadge, 0)                     AS HasGoldBadge,
    COALESCE(ua.AnswerCount, 0)                      AS TotalAnswers,
    ROUND(COALESCE(ua.AvgAnswerScore, 0), 2)         AS AvgAnswerScore,
    ua.LastAnswerDate,
    tg.Tag                                           AS TopTag,
    tg.TagAnswerCount,
    lp.Comment                                       AS LatestCloseReason,
    CASE
        WHEN lp.PostHistoryTypeId = 10 THEN 'Closed'
        WHEN lp.PostHistoryTypeId = 11 THEN 'Reopened'
        ELSE 'Other'
    END                                              AS LatestStatus
FROM UserReputation ur
LEFT JOIN UserGoldBadge ug       ON ur.UserId = ug.UserId
LEFT JOIN UserAnswerStats ua    ON ur.UserId = ua.UserId
LEFT JOIN UserTagActivity tg    ON ur.UserId = tg.UserId AND tg.TagRank = 1
LEFT JOIN LatestPostHistory lp  ON lp.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = ur.UserId
          AND p.PostTypeId = 1                -- Questions
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
    AND lp.rn = 1
WHERE ur.RepRank <= 1000
  AND ur.Reputation > 0
ORDER BY ur.RepRank
LIMIT 100

UNION ALL

SELECT
    NULL                                            AS UserId,
    'Median Reputation'                             AS DisplayName,
    mr.MedianRep                                    AS Reputation,
    NULL                                            AS RepRank,
    NULL                                            AS HasGoldBadge,
    NULL                                            AS TotalAnswers,
    NULL                                            AS AvgAnswerScore,
    NULL                                            AS LastAnswerDate,
    NULL                                            AS TopTag,
    NULL                                            AS TagAnswerCount,
    NULL                                            AS LatestCloseReason,
    NULL                                            AS LatestStatus
FROM MedianReputation mr
WHERE 1 = 1;
