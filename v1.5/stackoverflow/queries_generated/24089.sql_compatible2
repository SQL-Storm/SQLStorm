WITH
  -- Top scored questions per user
  top_posts AS (
    SELECT
        p.Id          AS post_id,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.Body,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score >= 50
  ),
  -- Tag frequency inside questions
  tag_pop AS (
    SELECT
        p.Id        AS post_id,
        t.tag_name,
        COUNT(*)    AS tag_occurrence
    FROM Posts p
    CROSS JOIN LATERAL (
      SELECT TRIM(BOTH '>' FROM unnest(string_to_array(p.Tags, '&gt;'))) AS tag_name
    ) t
    GROUP BY p.Id, t.tag_name
  )
SELECT
  t.post_id,
  t.tag_name,
  t.tag_occurrence
FROM tag_pop t
ORDER BY t.post_id, t.tag_name;