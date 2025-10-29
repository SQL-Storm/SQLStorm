-- {"query": "5937.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 522}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
TagPopularity AS (
  SELECT
    TRIM(tag) AS TagName,
    p.Id AS PostId,
    p.LastActivityDate
  FROM Posts p,
  LATERAL (
    SELECT value AS tag
    FROM (
      SELECT regexp_split_to_table(
        SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2),
        '><'
      ) AS value
    ) s
  ) split
  WHERE p.PostTypeId = 1
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM TagPopularity t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
  ORDER BY COUNT(*) DESC, AVG(p.Score) DESC
  LIMIT 20
),
CrossJoinHints AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.OwnerUserId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    tt.TagName
  FROM RecentActivePosts r
  JOIN TopTags tt
    ON EXISTS (
      SELECT 1
      FROM (
        SELECT regexp_split_to_table(
          SUBSTR(r.Tags, 2, LENGTH(r.Tags) - 2),
          '><'
        ) AS tag
      ) tparts
      WHERE tparts.tag = tt.TagName
    )
),
Windowed AS (
  SELECT
    cjh.PostId,
    cjh.PostTypeId,
    cjh.OwnerUserId,
    cjh.Title,
    cjh.Tags,
    cjh.CreationDate,
    cjh.LastActivityDate,
    cjh.Score,
    cjh.ViewCount,
    cjh.CommentCount,
    cjh.AnswerCount,
    cjh.FavoriteCount,
    cjh.TagName,
    ROW_NUMBER() OVER (
      PARTITION BY cjh.TagName
      ORDER BY cjh.LastActivityDate DESC, cjh.Score DESC
    ) AS rn_in_tag
  FROM CrossJoinHints cjh
)
SELECT
  w.TagName,
  w.PostId,
  w.Title,
  w.OwnerUserId,
  w.CreationDate,
  w.LastActivityDate,
  w.Score,
  w.ViewCount,
  w.CommentCount,
  w.AnswerCount,
  w.FavoriteCount,
  w.TagName AS TagCluster
FROM Windowed w
WHERE w.rn_in_tag = 1
ORDER BY w.TagName, w.LastActivityDate DESC;