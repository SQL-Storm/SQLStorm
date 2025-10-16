WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.PostTypeId,
    COALESCE(p.OwnerDisplayName, u.DisplayName) AS DisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.ClosedDate IS NULL
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY)
),
TopQuestionTags AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.DisplayName,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.LastActivityDate,
    rp.PostTypeId,
    TRIM(BOTH ' ' FROM t.t) AS TagName
  FROM RankedPosts rp
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(rp.Tags, 2, LENGTH(rp.Tags) - 2), '><')) AS t
  ) t
  WHERE rp.PostTypeId = 1
),
TagCorrelation AS (
  SELECT
    t1.TagName,
    COUNT(*) AS PostCount,
    AVG(t1.Score) AS AvgScore,
    MAX(t1.ViewCount) AS MaxViews
  FROM TopQuestionTags t1
  GROUP BY t1.TagName
),
TrendingTags AS (
  SELECT
    TagName,
    PostCount,
    AvgScore,
    MaxViews,
    ROW_NUMBER() OVER (ORDER BY PostCount DESC, AvgScore DESC) AS rn
  FROM TagCorrelation
)
SELECT
  tt.TagName AS tag,
  tt.PostCount,
  tt.AvgScore,
  tt.MaxViews,
  t1.Id AS QuestionId,
  t1.Title AS QuestionTitle,
  t1.DisplayName AS AskedBy,
  t1.CreationDate AS AskedOn,
  t1.ViewCount AS Views,
  t1.Score AS Score,
  t1.LastActivityDate AS LastActivity
FROM TrendingTags tt
JOIN TopQuestionTags t1 ON t1.TagName = tt.TagName
JOIN (
  SELECT
    Id,
    unnest(string_to_array(substr(Tags, 2, LENGTH(Tags) - 2), '><')) AS t
  FROM Posts
  WHERE PostTypeId = 1
) dt ON dt.Id = t1.Id
ORDER BY tt.rn, tt.TagName
LIMIT 100;