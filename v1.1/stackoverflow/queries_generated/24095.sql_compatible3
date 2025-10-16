WITH
  TaggedPosts AS (
    SELECT
      t.TagName,
      t.Count AS tag_count,
      p_all.Id AS post_id,
      p_all.Score AS post_score,
      p_all.OwnerUserId AS owner_id,
      p_all.LastActivityDate,
      p_all.Title,
      p_all.ViewCount,
      p_all.CreationDate
    FROM Tags t
    JOIN (
      SELECT Id, Score, OwnerUserId, LastActivityDate, Title, ViewCount, CreationDate, Tags
      FROM Posts
      WHERE PostTypeId = 1
    ) p_all ON p_all.Tags LIKE '%' || t.TagName || '%'
  ),
  PostVotes AS (
    SELECT
      pv.PostId,
      SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1
               WHEN pv.VoteTypeId = 3 THEN -1
               ELSE 0 END) AS net_votes,
      SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
      SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes pv
    GROUP BY pv.PostId
  ),
  TagAggregates AS (
    SELECT
      tp.TagName,
      COUNT(*) AS linked_posts,
      AVG(tp.post_score) AS avg_score,
      SUM(COALESCE(pv.net_votes, 0)) AS total_net_votes,
      STRING_AGG(DISTINCT COALESCE(CAST(tp.owner_id AS varchar), '-1'), ',') AS owners
    FROM TaggedPosts tp
    LEFT JOIN PostVotes pv
      ON pv.PostId = tp.post_id
    GROUP BY tp.TagName
  ),
  ActivityWindow AS (
    SELECT
      ta.TagName,
      ta.linked_posts,
      ta.avg_score,
      ta.total_net_votes,
      ta.owners,
      RANK() OVER (ORDER BY ta.total_net_votes DESC) AS vn_rnk,
      NULLIF(SUM(ABS(ta.avg_score)) OVER (), 0) AS norm_factor
    FROM TagAggregates ta
    GROUP BY
      ta.TagName,
      ta.linked_posts,
      ta.avg_score,
      ta.total_net_votes,
      ta.owners
  ),
  SetOps AS (
    SELECT
      aw.TagName,
      aw.linked_posts,
      aw.avg_score,
      aw.total_net_votes,
      aw.owners,
      aw.vn_rnk
    FROM ActivityWindow aw

    UNION ALL

    SELECT
      'All' AS TagName,
      SUM(linked_posts) AS linked_posts,
      SUM(avg_score) AS avg_score,
      SUM(total_net_votes) AS total_net_votes,
      NULL AS owners,
      NULL AS vn_rnk
    FROM ActivityWindow
  )
SELECT
  so.TagName,
  so.linked_posts,
  so.avg_score,
  so.total_net_votes,
  so.owners,
  CASE
    WHEN so.total_net_votes > 0 THEN '+' || CAST(ROUND(CAST(so.total_net_votes AS numeric), 0) AS varchar)
    WHEN so.total_net_votes < 0 THEN '-' || CAST(ROUND(CAST(ABS(so.total_net_votes) AS numeric), 0) AS varchar)
    ELSE '0'
  END AS net_vote_str,
  ('https://stackoverflow.com/tags/' || LOWER(so.TagName)) AS tag_url,
  so.vn_rnk
FROM SetOps so
WHERE
  ((so.TagName <> 'All' AND so.linked_posts > 10) OR so.TagName = 'All')
  AND (so.avg_score > 0 OR so.avg_score IS NULL)
ORDER BY
  CASE WHEN so.TagName = 'All' THEN 9999 ELSE COALESCE(so.vn_rnk, 9998) END,
  so.total_net_votes DESC
LIMIT 20;