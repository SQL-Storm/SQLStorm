-- {"query": "5145.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 732}
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditDate,
    p.LastEditorUserId,
    p.OwnerDisplayName,
    p.ContentLicense,
    COALESCE(a.Score, 0) AS AcceptedScore
  FROM Posts p
  LEFT JOIN Posts a ON a.Id = p.AcceptedAnswerId
),
Aggs AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.PostTypeId,
    rp.Tags,
    rp.ViewCount,
    rp.Score,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Body,
    rp.LastEditDate,
    rp.LastEditorUserId,
    rp.OwnerDisplayName,
    rp.ContentLicense,
    rp.AcceptedScore,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(rp.CreationDate AS DATE), rp.PostTypeId
      ORDER BY rp.Score DESC, rp.ViewCount DESC
    ) AS RnkDayType
  FROM RankedPosts rp
),
ZeroDiff AS (
  SELECT
    a.*,
    (SELECT COUNT(*) FROM Comments c
     WHERE c.PostId = a.Id AND c.UserId = a.OwnerUserId) AS UserCommentCount
  FROM Aggs a
),
Final AS (
  SELECT
    z.Id,
    z.Title,
    z.CreationDate,
    z.OwnerUserId,
    z.PostTypeId,
    z.Tags,
    z.ViewCount,
    z.Score,
    z.AcceptedAnswerId,
    z.ParentId,
    z.LastActivityDate,
    z.CommentCount,
    z.FavoriteCount,
    z.Body,
    z.LastEditDate,
    z.LastEditorUserId,
    z.OwnerDisplayName,
    z.ContentLicense,
    z.AcceptedScore,
    z.RnkDayType,
    z.UserCommentCount,
    CASE
      WHEN z.RnkDayType = 1 THEN 'TopOfDay'
      ELSE 'Other'
    END AS BenchmarkTag
  FROM ZeroDiff z
  UNION ALL
  SELECT
    CAST(NULL AS INTEGER) AS Id,
    CAST(NULL AS VARCHAR) AS Title,
    CAST(NULL AS TIMESTAMP) AS CreationDate,
    CAST(NULL AS INTEGER) AS OwnerUserId,
    CAST(NULL AS SMALLINT) AS PostTypeId,
    CAST(NULL AS VARCHAR) AS Tags,
    CAST(NULL AS INTEGER) AS ViewCount,
    CAST(NULL AS INTEGER) AS Score,
    CAST(NULL AS INTEGER) AS AcceptedAnswerId,
    CAST(NULL AS INTEGER) AS ParentId,
    CAST(NULL AS TIMESTAMP) AS LastActivityDate,
    CAST(NULL AS INTEGER) AS CommentCount,
    CAST(NULL AS INTEGER) AS FavoriteCount,
    CAST(NULL AS TEXT) AS Body,
    CAST(NULL AS TIMESTAMP) AS LastEditDate,
    CAST(NULL AS INTEGER) AS LastEditorUserId,
    CAST(NULL AS VARCHAR) AS OwnerDisplayName,
    CAST(NULL AS VARCHAR) AS ContentLicense,
    CAST(NULL AS INTEGER) AS AcceptedScore,
    CAST(NULL AS INTEGER) AS RnkDayType,
    CAST(NULL AS INTEGER) AS UserCommentCount,
    'Synthetic' AS BenchmarkTag
  WHERE NOT EXISTS (SELECT 1)
)
SELECT *
FROM Final;