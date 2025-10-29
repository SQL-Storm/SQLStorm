-- {"query": "5242.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 770}
WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.Body,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END AS HighViewPost,
    CASE
      WHEN p.Score >= 10 THEN 'HighScore'
      WHEN p.Score >= 0 THEN 'Neutral'
      ELSE 'LowScore'
    END AS ScoreBand
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
tag_expansion AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ra.Score,
    ra.ViewCount,
    ra.Tags,
    ra.Body,
    ra.CommentCount,
    ra.AnswerCount,
    ra.FavoriteCount,
    ra.HighViewPost,
    ra.ScoreBand,
    TRIM(BOTH ' ' FROM t.tag) AS TagName
  FROM recent_activity ra
  LEFT JOIN Users u ON ra.OwnerUserId = u.Id
  CROSS JOIN LATERAL (
    SELECT value AS tag
    FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(ra.Tags FROM 2 FOR CHAR_LENGTH(ra.Tags)-2), '><')) AS t(value)
  ) AS t
),
tag_recent AS (
  SELECT
    te.PostId,
    te.Title,
    te.OwnerUserId,
    te.OwnerDisplayName,
    te.Score,
    te.ViewCount,
    te.Body,
    te.TagName,
    te.LastActivityDate AS ActivityDate,
    te.ScoreBand,
    te.HighViewPost
  FROM tag_expansion te
),
qualified AS (
  SELECT
    tr.PostId,
    tr.Title,
    tr.OwnerUserId,
    tr.OwnerDisplayName,
    tr.Score,
    tr.ViewCount,
    tr.Body,
    tr.TagName,
    tr.ActivityDate,
    tr.ScoreBand,
    tr.HighViewPost,
    '{'
      || '"length": ' || CAST(CHAR_LENGTH(TRIM(tr.Body)) AS VARCHAR) || ', '
      || '"words": ' || CAST(COALESCE(array_length(regexp_split_to_array(TRIM(tr.Body), '\s+'), 1), 0) AS VARCHAR) || ', '
      || '"tag": ' || '"' || REPLACE(COALESCE(tr.TagName, ''), '"', '\"') || '"'
      || '}' AS MetaInfo
  FROM tag_recent tr
  WHERE tr.TagName IS NOT NULL
),
ranked AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.Score,
    q.ViewCount,
    q.Body,
    q.TagName,
    q.ActivityDate,
    q.ScoreBand,
    q.HighViewPost,
    q.MetaInfo,
    ROW_NUMBER() OVER (
      PARTITION BY q.TagName
      ORDER BY q.ActivityDate DESC,
               q.Score DESC,
               q.ViewCount DESC
    ) AS rn
  FROM qualified q
  WHERE q.ActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
)
SELECT
  r.PostId,
  r.Title,
  r.OwnerUserId,
  r.OwnerDisplayName,
  r.Score,
  r.ViewCount,
  r.Body,
  r.TagName,
  r.ActivityDate,
  r.ScoreBand,
  r.HighViewPost,
  r.MetaInfo
FROM ranked r
WHERE r.rn <= 5
GROUP BY
  r.PostId,
  r.Title,
  r.OwnerUserId,
  r.OwnerDisplayName,
  r.Score,
  r.ViewCount,
  r.Body,
  r.TagName,
  r.ActivityDate,
  r.ScoreBand,
  r.HighViewPost,
  r.MetaInfo,
  r.rn
ORDER BY r.TagName, r.ActivityDate DESC;