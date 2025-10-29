-- {"query": "5271.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 749}
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location AS OwnerLocation,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        (CASE WHEN p.PostTypeId = 1 THEN p.Score * 1.5 ELSE p.Score END)
        + COALESCE(p.ViewCount, 0) * 0.2
        + EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) * -0.001
        + COALESCE(u.Reputation, 0) * 0.01
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
star_cross AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.OwnerLocation,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    (
      SELECT MAX(pl.RelatedPostId)
      FROM PostLinks pl
      WHERE pl.PostId = rp.PostId
        AND pl.LinkTypeId = 1
    ) AS TopLinkedPostId,
    (
      SELECT AVG(t.Count)
      FROM Tags t
      WHERE t.TagName IN (
        -- Split tags like '<tag1><tag2>' into individual tag names without angle brackets.
        -- Use standard SQL: replace '<' with '' then split on '>' and filter out empty strings.
        -- Implement splitting via a correlated subquery that extracts nth segment.
        SELECT seg.tag
        FROM (
          SELECT TRIM(seg) AS tag
          FROM (
            -- Generate sequence up to a reasonable max tags per post (e.g., 50)
            SELECT SUBSTRING(REPLACE(rp.Tags, '<', '') FROM (CASE WHEN pos+1 <= LENGTH(REPLACE(rp.Tags, '<', '')) THEN pos+1 ELSE NULL END) FOR 
                   (CASE WHEN next_pos IS NOT NULL THEN next_pos - pos - 1 ELSE LENGTH(REPLACE(rp.Tags, '<', '')) - pos END)) AS seg
            FROM (
              -- compute positions of '>' characters
              SELECT
                generate_pos.pos,
                LEAD(generate_pos.pos) OVER (ORDER BY generate_pos.pos) AS next_pos
              FROM (
                SELECT 0 AS pos
                UNION ALL
                SELECT instr.seq_pos
                FROM (
                  -- build sequence of positions of '>' in the string
                  SELECT (
                    SELECT MIN(p_pos) FROM (
                      VALUES (1)
                    ) v(p_pos)
                  ) AS seq_pos
                ) instr
              ) generate_pos
            ) pos_table
          ) sub_segs
        ) seg
        WHERE seg.tag <> ''
      )
    ) AS AvgTagCount
  FROM ranked_posts rp
  WHERE rp.rn <= 50
),
hat AS (
  SELECT
    sc.PostId,
    sc.Title,
    sc.Tags,
    sc.CreationDate,
    sc.Score,
    sc.ViewCount,
    sc.OwnerUserId,
    sc.OwnerDisplayName,
    sc.Reputation,
    sc.OwnerLocation,
    sc.LastActivityDate,
    sc.CommentCount,
    sc.AnswerCount,
    sc.FavoriteCount,
    sc.ContentLicense,
    sc.TopLinkedPostId,
    sc.AvgTagCount,
    pld.Name AS PostHistoryTypeName
  FROM star_cross sc
  LEFT JOIN Posts p ON sc.PostId = p.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN PostHistoryTypes pld ON ph.PostHistoryTypeId = pld.Id
  WHERE (pld.Name LIKE '%Initial%' OR pld.Name LIKE '%Post Closed%')
)
SELECT
  h.PostId,
  h.Title,
  h.Tags,
  h.CreationDate,
  h.Score,
  h.ViewCount,
  h.OwnerDisplayName,
  h.Reputation,
  h.OwnerLocation,
  h.LastActivityDate,
  h.CommentCount,
  h.AnswerCount,
  h.FavoriteCount,
  h.ContentLicense,
  COALESCE(h.PostHistoryTypeName, 'Unknown') AS HistoryType,
  h.TopLinkedPostId,
  h.AvgTagCount
FROM hat h
ORDER BY h.CreationDate DESC
LIMIT 100;