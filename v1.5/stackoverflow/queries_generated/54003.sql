-- {"query": "54003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2281} 

WITH user_posts AS (
    SELECT
        u.Id            AS UserId,
        u.DisplayName   AS DisplayName,
        u.Reputation    AS Reputation,
        p.Id            AS PostId,
        p.PostTypeId    AS PostTypeId,
        p.Tags          AS Tags,
        p.Score         AS Score
    FROM Users u
    JOIN Posts p
      ON p.OwnerUserId = u.Id
),
question_stats AS (
    SELECT
        UserId,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(Score) FILTER (WHERE PostTypeId = 1) AS AvgQScore,
        AVG(Score) FILTER (WHERE PostTypeId = 2) AS AvgAScore
    FROM user_posts
    GROUP BY UserId
),
tag_counts AS (
    SELECT
        UserId,
        UNNEST(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS Tag
    FROM user_posts
    WHERE PostTypeId = 1
),
top_tags AS (
    SELECT
        UserId,
        Tag,
        COUNT(*)  AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY COUNT(*) DESC) AS rn
    FROM tag_counts
    GROUP BY UserId, Tag
)
SELECT
    u.Id            AS UserId,
    u.DisplayName,
    u.Reputation,
    qs.Questions,
    qs.Answers,
    qs.AvgQScore,
    qs.AvgAScore,
    STRING_AGG(tt.Tag || ' (' || tt.TagCount || ')', ', ')
        FILTER (WHERE tt.rn <= 3) AS TopTags
FROM Users u
JOIN question_stats qs
  ON qs.UserId = u.Id
LEFT JOIN top_tags tt
  ON tt.UserId = qs.UserId
GROUP BY u.Id, u.DisplayName, u.Reputation,
         qs.Questions, qs.Answers, qs.AvgQScore, qs.AvgAScore
ORDER BY qs.Questions DESC, qs.Answers DESC
LIMIT 20;
