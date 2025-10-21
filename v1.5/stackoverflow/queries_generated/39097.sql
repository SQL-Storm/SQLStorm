-- {"query": "39097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 1832} 

WITH recent_questions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName AS AuthorName
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
),
answer_metrics AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) FILTER (WHERE a.Score >= 0)              AS TotalAnswers,
        AVG(a.CreationDate - q.CreationDate)                 AS AvgAnswerDelay,
        MAX(a.Score)                                         AS TopAnswerScore
    FROM recent_questions AS q
    LEFT JOIN Posts AS a
      ON a.ParentId = q.Id
     AND a.PostTypeId = 2
    GROUP BY q.Id
),
comment_metrics AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id)          AS TotalComments,
        AVG(c.Score)         AS AvgCommentScore
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON c.PostId = p.Id
    GROUP BY p.Id
),
badge_leaderboard AS (
    SELECT
        u.Id                               AS UserId,
        COUNT(b.Id)                        AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS u
    LEFT JOIN Badges AS b
      ON b.UserId = u.Id
    GROUP BY u.Id
),
top_tags AS (
    SELECT
        unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS TagName,
        COUNT(*) AS QuestionCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY 1
    ORDER BY COUNT(*) DESC
    LIMIT 10
)
SELECT
    q.Title,
    q.AuthorName,
    am.TotalAnswers,
    am.AvgAnswerDelay,
    am.TopAnswerScore,
    cm.TotalComments,
    cm.AvgCommentScore,
    bl.GoldBadges,
    bl.SilverBadges,
    bl.BronzeBadges,
    tp.TagName,
    tp.QuestionCount
FROM recent_questions AS q
JOIN answer_metrics AS am
  ON am.QuestionId = q.Id
LEFT JOIN comment_metrics AS cm
  ON cm.PostId = q.Id
LEFT JOIN badge_leaderboard AS bl
  ON bl.UserId = q.OwnerUserId
LEFT JOIN LATERAL (
    SELECT t.TagName, t.QuestionCount
    FROM top_tags AS t
    WHERE t.TagName = ANY(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><'))
    LIMIT 1
) AS tp ON TRUE
ORDER BY am.TotalAnswers DESC, cm.TotalComments DESC
LIMIT 10;
