-- {"query": "39074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2259} 

WITH 
RecentQuestions AS (
    SELECT p.Id,
           p.CreationDate,
           p.AcceptedAnswerId,
           p.Tags,
           p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
ExpandedTags AS (
    SELECT
        rq.Id            AS QuestionId,
        unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) AS Tag,
        rq.CreationDate,
        rq.AcceptedAnswerId,
        rq.OwnerUserId
    FROM RecentQuestions rq
),
TagMetrics AS (
    SELECT
        et.Tag,
        COUNT(*)                                               AS QuestionCount,
        AVG(q.ViewCount)                                       AS AvgViews,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - et.CreationDate)) / 3600) AS AvgAnswerDelayHours
    FROM ExpandedTags et
    JOIN Posts q   ON q.Id     = et.QuestionId
    JOIN Posts a   ON a.ParentId = et.QuestionId
    GROUP BY et.Tag
),
TopTags AS (
    SELECT
        Tag,
        QuestionCount,
        AvgViews,
        AvgAnswerDelayHours,
        RANK() OVER (ORDER BY QuestionCount DESC)              AS rk
    FROM TagMetrics
    WHERE QuestionCount >= 50
),
Top5Tags AS (
    SELECT Tag, QuestionCount, AvgViews, AvgAnswerDelayHours
    FROM TopTags
    WHERE rk <= 5
),
AnswerActivity AS (
    SELECT
        et.Tag,
        a.OwnerUserId                  AS AnswererId,
        COUNT(*)                       AS AnswersProvided,
        AVG(a.Score)                   AS AvgAnswerScore,
        RANK() OVER (PARTITION BY et.Tag ORDER BY COUNT(*) DESC) AS AnswerRank
    FROM ExpandedTags et
    JOIN Posts a
      ON a.ParentId = et.QuestionId
     AND a.PostTypeId = 2
    GROUP BY et.Tag, a.OwnerUserId
),
TopAnswerers AS (
    SELECT
        aa.Tag,
        aa.AnswererId,
        aa.AnswersProvided,
        aa.AvgAnswerScore
    FROM AnswerActivity aa
    WHERE aa.AnswerRank <= 3
),
UserBadges AS (
    SELECT
        u.Id AS UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
)
SELECT
    t.Tag,
    t.QuestionCount,
    ROUND(t.AvgViews, 2)            AS AvgViews,
    ROUND(t.AvgAnswerDelayHours, 2) AS AvgAnswerDelayHours,
    JSON_AGG(
      JSON_BUILD_OBJECT(
        'AnswererId', ta.AnswererId,
        'Answers',    ta.AnswersProvided,
        'AvgScore',   ROUND(ta.AvgAnswerScore, 2),
        'Badges',     JSON_BUILD_OBJECT(
                         'Gold',   COALESCE(ub.GoldBadges,   0),
                         'Silver', COALESCE(ub.SilverBadges, 0),
                         'Bronze', COALESCE(ub.BronzeBadges, 0)
                     )
      )
      ORDER BY ta.AnswersProvided DESC
    ) AS TopAnswerers
FROM Top5Tags t
LEFT JOIN TopAnswerers ta ON ta.Tag = t.Tag
LEFT JOIN UserBadges  ub ON ub.UserId = ta.AnswererId
GROUP BY
    t.Tag,
    t.QuestionCount,
    t.AvgViews,
    t.AvgAnswerDelayHours
ORDER BY
    t.QuestionCount DESC;
