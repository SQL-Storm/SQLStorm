-- {"query": "39079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2603} 

WITH
RecentQuestions AS (
    SELECT
        p.Id           AS QuestionId,
        p.OwnerUserId,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= current_date - INTERVAL '365 days'
),
TagExplode AS (
    SELECT
        rq.QuestionId,
        rq.OwnerUserId,
        rq.CreationDate    AS QuestionDate,
        tag.TagName
    FROM RecentQuestions rq
    CROSS JOIN LATERAL
        unnest(
            string_to_array(
                substring(rq.Tags, 2, length(rq.Tags) - 2),
                '><'
            )
        ) AS tag(TagName)
),
FirstAnswers AS (
    SELECT
        p.ParentId    AS QuestionId,
        MIN(p.CreationDate) AS FirstAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
TagAggregates AS (
    SELECT
        te.TagName,
        COUNT(DISTINCT te.QuestionId)                      AS QuestionCount,
        ROUND(
          AVG(
            EXTRACT(
              EPOCH FROM (fa.FirstAnswerDate - te.QuestionDate)
            )
          )/3600
        ,2)                                               AS AvgResponseHours
    FROM TagExplode te
    LEFT JOIN FirstAnswers fa
      ON fa.QuestionId = te.QuestionId
    GROUP BY te.TagName
),
TopTags AS (
    SELECT TagName
    FROM TagAggregates
    ORDER BY QuestionCount DESC
    LIMIT 10
),
UserTagActivity AS (
    SELECT
        p.OwnerUserId         AS UserId,
        te.TagName,
        COUNT(*)              AS AnswersCount
    FROM Posts p
    JOIN TagExplode te
      ON p.ParentId = te.QuestionId
     AND p.PostTypeId = 2
    GROUP BY p.OwnerUserId, te.TagName
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    tt.TagName,
    ta.QuestionCount,
    ta.AvgResponseHours,
    uta.UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(ubc.GoldBadges,   0) AS GoldBadges,
    COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
    uta.AnswersCount,
    RANK() OVER (
      PARTITION BY tt.TagName
      ORDER BY uta.AnswersCount DESC
    ) AS UserRank
FROM TopTags tt
JOIN TagAggregates ta
  ON ta.TagName = tt.TagName
LEFT JOIN UserTagActivity uta
  ON uta.TagName = tt.TagName
LEFT JOIN Users u
  ON u.Id = uta.UserId
LEFT JOIN UserBadgeCounts ubc
  ON ubc.UserId = u.Id
WHERE uta.AnswersCount IS NOT NULL
  AND RANK() OVER (
        PARTITION BY tt.TagName
        ORDER BY uta.AnswersCount DESC
      ) <= 3
ORDER BY ta.QuestionCount DESC, UserRank;
