WITH
  q_stats AS (
    SELECT
      p.Id                      AS qid,
      p.Title,
      COALESCE(a.cnt,0)         AS answer_cnt,
      COALESCE(c.cnt,0)         AS comment_cnt,
      COALESCE(v.cnt,0)         AS vote_cnt,
      p.Score,
      p.ViewCount,
      p.Tags,
      p.CreationDate,
      u.Reputation              AS user_rep,
      MAX(ph.CreationDate)     AS last_edit
    FROM Posts p
    LEFT JOIN (
      SELECT ParentId, COUNT(*) AS cnt
      FROM Posts
      WHERE PostTypeId = 2
      GROUP BY ParentId
    ) a ON a.ParentId = p.Id
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS cnt
      FROM Comments
      GROUP BY PostId
    ) c ON c.PostId = p.Id
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS cnt
      FROM Votes
      WHERE VoteTypeId IN (2,3)
      GROUP BY PostId
    ) v ON v.PostId = p.Id
    JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph
      ON ph.PostId = p.Id
     AND ph.PostHistoryTypeId IN (5,6)
    WHERE p.PostTypeId = 1
    GROUP BY
      p.Id, p.Title, a.cnt, c.cnt, v.cnt,
      p.Score, p.ViewCount, p.Tags,
      p.CreationDate, u.Reputation
  ),

  -- split tags by delimiter '><' using recursive standard SQL
  tags_split AS (
    SELECT
      qid,
      TRIM(BOTH '<>' FROM tag) AS tag
    FROM (
      SELECT
        qid,
        tag
      FROM (
        SELECT
          qid,
          Tags AS rest,
          CAST(NULL AS VARCHAR) AS tag,
          0 AS step
        FROM q_stats

        UNION ALL

        SELECT
          qid,
          -- next rest (we keep a large length to emulate "rest of string")
          SUBSTR(rest,
                 CASE
                   WHEN POSITION('><' IN rest) = 0 THEN 1
                   ELSE POSITION('><' IN rest) + 2
                 END,
                 4000000
                ) AS rest,
          CASE
            WHEN POSITION('><' IN rest) = 0 THEN rest
            ELSE SUBSTR(rest, 1, POSITION('><' IN rest)-1)
          END AS tag,
          step + 1
        FROM (
          SELECT qid, Tags AS rest, 0 AS step
          FROM q_stats
        ) s
        WHERE rest IS NOT NULL
      ) x
      WHERE tag IS NOT NULL
    ) y
  ),

  tags_rank AS (
    SELECT
      qid,
      tag,
      ROW_NUMBER() OVER (PARTITION BY qid ORDER BY tag) AS tag_rank
    FROM tags_split
  ),

  dup_rel AS (
    SELECT
      pl.PostId        AS dup_post,
      pl.RelatedPostId AS dup_of,
      p1.Title         AS dup_title,
      p2.Title         AS dup_of_title
    FROM PostLinks pl
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId = 3
  ),

  cat AS (
    SELECT
      qid,
      CASE
        WHEN Score > 2000 AND answer_cnt < 5 THEN 'Precious'
        WHEN Score <  10 AND answer_cnt > 20 THEN 'Rat'
        ELSE 'Standard'
      END AS category
    FROM q_stats
  ),

  full_stats AS (
    SELECT
      q.qid,
      q.Title,
      q.Score,
      q.ViewCount,
      q.answer_cnt,
      q.comment_cnt,
      q.vote_cnt,
      q.last_edit,
      q.user_rep,
      STRING_AGG(t.tag, ',' ORDER BY t.tag_rank) AS tags_ordered,
      COALESCE(d.dup_of, -1) AS duplicate_of,
      c.category
    FROM q_stats q
    LEFT JOIN tags_rank t ON t.qid = q.qid
    LEFT JOIN dup_rel d ON d.dup_post = q.qid
    JOIN cat c ON c.qid = q.qid
    GROUP BY
      q.qid, q.Title, q.Score, q.ViewCount,
      q.answer_cnt, q.comment_cnt, q.vote_cnt,
      q.last_edit, q.user_rep,
      d.dup_of, c.category
  )

SELECT
  fs.*,
  ( SELECT COUNT(*)
    FROM Posts p2
    WHERE p2.ParentId = fs.qid
      AND p2.AcceptedAnswerId IS NOT NULL ) AS accepted_by_author
FROM full_stats fs
WHERE fs.Score BETWEEN 3 AND 5000
  AND fs.answer_cnt > 0
ORDER BY fs.Score DESC, fs.answer_cnt DESC
LIMIT 100;