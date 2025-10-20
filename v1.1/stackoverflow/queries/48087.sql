WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS rn,
    p.Tags,
    p.OwnerUserId
  FROM Posts AS p
  WHERE
    p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
),
TopTags AS (
  SELECT
    SUBSTRING(tag_value FROM 2 FOR (CHAR_LENGTH(tag_value) - 2)) AS TagName,
    COUNT(*) AS TagCount
  FROM Posts,
    UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(Tags, '<', ''), '>', ''), ',')) AS t(tag_value)
  WHERE
    PostTypeId = 1
    AND ClosedDate IS NULL
    AND CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
  GROUP BY
    SUBSTRING(tag_value FROM 2 FOR (CHAR_LENGTH(tag_value) - 2))
  ORDER BY
    TagCount DESC
  LIMIT 10
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.ViewCount) AS AverageViewCount
  FROM Users AS u
  JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  WHERE
    p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
  GROUP BY
    u.Id,
    u.DisplayName
  ORDER BY
    PostCount DESC
  LIMIT 5
)
SELECT
  rp.PostId,
  rp.Title,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.AnswerCount,
  rp.CommentCount,
  (
    SELECT
      STRING_AGG(tt.TagName, ',')
    FROM TopTags AS tt
    WHERE
      rp.Title LIKE '%' || tt.TagName || '%' OR rp.Tags LIKE '%' || tt.TagName || '%'
  ) AS RelatedTopTags,
  (
    SELECT
      ua.DisplayName
    FROM UserActivity AS ua
    WHERE
      ua.UserId = (
        SELECT p2.OwnerUserId
        FROM Posts p2
        WHERE p2.Id = rp.PostId
      )
  ) AS TopAuthorDisplayName
FROM RankedPosts AS rp
WHERE
  rp.rn <= 100;