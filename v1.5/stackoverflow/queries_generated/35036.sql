-- {"query": "35036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 664} 
WITH recent_questions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '90 days'
),
top_answerers AS (
    SELECT
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererId,
        COUNT(*) AS AnswerCount,
        SUM(a.Score) AS TotalScore
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate > NOW() - INTERVAL '90 days'
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.ParentId, a.OwnerUserId
    HAVING COUNT(*) >= 2
),
popular_tags AS (
    SELECT
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS Tag,
        COUNT(*) AS UsageCount
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.CreationDate > NOW() - INTERVAL '90 days'
    GROUP BY Tag
    HAVING COUNT(*) > 20
),
tagged_questions AS (
    SELECT
        q.Id AS QuestionId,
        pt.Tag
    FROM Posts q
    CROSS JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS pt(Tag)
    WHERE q.PostTypeId = 1
      AND q.CreationDate > NOW() - INTERVAL '90 days'
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    u.DisplayName AS QuestionOwner,
    ta.AnswererId,
    u2.DisplayName AS TopAnswerer,
    ta.AnswerCount,
    ta.TotalScore,
    array_agg(DISTINCT tq.Tag ORDER BY tq.Tag) AS TopTags,
    COALESCE(b.BadgeCount, 0) AS TopAnswererBadges
FROM recent_questions rq
LEFT JOIN top_answerers ta ON ta.QuestionId = rq.QuestionId
LEFT JOIN Users u ON u.Id = rq.OwnerUserId
LEFT JOIN Users u2 ON u2.Id = ta.AnswererId
LEFT JOIN tagged_questions tq ON tq.QuestionId = rq.QuestionId
    AND tq.Tag IN (SELECT Tag FROM popular_tags)
LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    WHERE Date > NOW() - INTERVAL '90 days'
    GROUP BY UserId
) b ON b.UserId = ta.AnswererId
WHERE rq.Score > 0 AND rq.ViewCount > 50
GROUP BY
    rq.QuestionId, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount,
    u.DisplayName, ta.AnswererId, u2.DisplayName, ta.AnswerCount, ta.TotalScore, b.BadgeCount
ORDER BY rq.ViewCount DESC, ta.TotalScore DESC NULLS LAST
LIMIT 100;