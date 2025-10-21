-- {"query": "39080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2979} 

WITH RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate)) / 86400 AS AgeDays,
        p.OwnerUserId,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT
        rq.Id             AS QuestionId,
        COUNT(a.Id)       AS TotalAnswers,
        AVG(a.Score)      AS AvgAnswerScore,
        EXTRACT(EPOCH FROM (MIN(a.CreationDate) - rq.CreationDate)) / 86400 AS TimeToFirstAnswer
    FROM RecentQuestions rq
    JOIN Posts a
      ON a.ParentId = rq.Id
     AND a.PostTypeId = 2
    GROUP BY rq.Id
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*)                                         AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1)              AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2)              AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3)              AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserEngagement AS (
    SELECT
        u.Id                AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(bs.TotalBadges, 0)  AS TotalBadges,
        COALESCE(bs.GoldBadges,  0)  AS GoldBadges,
        COALESCE(bs.SilverBadges,0)  AS SilverBadges,
        COALESCE(bs.BronzeBadges,0)  AS BronzeBadges,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId IN (1,2)) AS NumPosts,
        COUNT(DISTINCT c.Id)                                  AS NumComments
    FROM Users u
    LEFT JOIN BadgeSummary bs
      ON bs.UserId = u.Id
    LEFT JOIN Posts p
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c
      ON c.UserId = u.Id
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        bs.TotalBadges,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges
),
TagStats AS (
    SELECT
        t.tag               AS TagName,
        COUNT(*)            AS QuestionCount,
        AVG(p.Score)        AS AvgScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(
        string_to_array(
            SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2),
            '><'
        )
    ) AS t(tag)
    WHERE p.PostTypeId = 1
    GROUP BY t.tag
)
SELECT
    rq.Id                   AS QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.AgeDays,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.TimeToFirstAnswer,
    ts.TagName,
    ts.QuestionCount,
    ts.AvgScore,
    ts.MedianScore,
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalBadges,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    ue.NumPosts,
    ue.NumComments
FROM RecentQuestions rq
JOIN AnswerStats ans
  ON ans.QuestionId = rq.Id
JOIN UserEngagement ue
  ON ue.UserId = rq.OwnerUserId
JOIN TagStats ts
  ON ts.TagName = ANY(
         string_to_array(
             SUBSTRING(rq.Tags, 2, LENGTH(rq.Tags) - 2),
             '><'
         )
     )
ORDER BY
    ans.TotalAnswers DESC,
    ans.AvgAnswerScore DESC,
    rq.CreationDate DESC
LIMIT 50;
