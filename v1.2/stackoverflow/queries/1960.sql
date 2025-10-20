WITH RecursiveAllTags (PostId, Tag, tag_len) AS (
  SELECT
    p.Id AS PostId,
    t.Tag AS Tag,
    LENGTH(t.Tag::VARCHAR) AS tag_len
  FROM Posts p,
  LATERAL (
    SELECT value AS Tag
    FROM UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><')) AS u(value)
  ) AS t
  WHERE p.PostTypeId = 1
    AND p.Tags IS NOT NULL
)
SELECT PostId, Tag, tag_len
FROM RecursiveAllTags;