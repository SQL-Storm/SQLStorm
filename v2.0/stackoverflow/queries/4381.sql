-- {"query": "4381.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1540}
WITH
  RankedPosts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.ClosedDate,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type
    FROM Posts AS p
    WHERE
      p.PostTypeId IN (1, 2)
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY
  ),
  UserPostStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(rp.Id) AS total_posts,
      SUM(rp.Score) AS total_score,
      AVG(rp.Score) AS avg_score,
      MAX(rp.CreationDate) AS last_post_date,
      CASE WHEN u.Reputation > 10000 THEN 'High Reputation' WHEN u.Reputation > 1000 THEN 'Medium Reputation' ELSE 'Low Reputation' END AS reputation_level
    FROM Users AS u
    LEFT JOIN RankedPosts AS rp
      ON u.Id = rp.OwnerUserId
    WHERE
      u.Id > 0
    GROUP BY
      u.Id,
      u.DisplayName,
      CASE WHEN u.Reputation > 10000 THEN 'High Reputation' WHEN u.Reputation > 1000 THEN 'Medium Reputation' ELSE 'Low Reputation' END
  ),
  PostComments AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS comment_count_per_post,
      SUM(c.Score) AS comment_score_sum,
      AVG(c.Score) AS avg_comment_score,
      MAX(c.CreationDate) AS last_comment_date
    FROM Comments AS c
    GROUP BY
      c.PostId
  ),
  AggregatedPostData AS (
    SELECT
      rp.Id AS PostId,
      rp.PostTypeId,
      rp.OwnerUserId,
      rp.Score,
      rp.AnswerCount,
      rp.CommentCount AS direct_comment_count,
      rp.FavoriteCount,
      rp.ViewCount,
      rp.ClosedDate,
      ups.DisplayName AS OwnerDisplayName,
      ups.reputation_level AS OwnerReputationLevel,
      pc.comment_count_per_post,
      pc.comment_score_sum,
      pc.avg_comment_score,
      CASE
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above Average'
        WHEN rp.Score < rp.avg_score_by_type * 0.5 THEN 'Below Average'
        ELSE 'Average'
      END AS score_vs_type_average,
      CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.Score > 50 AND rp.AnswerCount > 5 THEN 'Popular'
        ELSE 'Standard'
      END AS post_status_category,
      rp.CreationDate
    FROM RankedPosts AS rp
    JOIN UserPostStats AS ups
      ON rp.OwnerUserId = ups.UserId
    LEFT JOIN PostComments AS pc
      ON rp.Id = pc.PostId
    WHERE
      rp.rn <= 100
  )
SELECT
  apd.PostId,
  apd.PostTypeId,
  apd.Score,
  apd.AnswerCount,
  apd.FavoriteCount,
  apd.ViewCount,
  apd.OwnerDisplayName,
  apd.OwnerReputationLevel,
  apd.comment_count_per_post,
  apd.avg_comment_score,
  apd.score_vs_type_average,
  apd.post_status_category,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = apd.PostId AND pl.LinkTypeId = 3
  ) AS duplicate_link_count,
  CASE
    WHEN apd.ClosedDate IS NOT NULL THEN EXTRACT(EPOCH FROM (apd.CreationDate - apd.ClosedDate)) / 60
    ELSE NULL
  END AS minutes_open_when_closed,
  CASE
    WHEN apd.OwnerReputationLevel = 'High Reputation' AND apd.Score > 100 THEN 'Influential High Rep User'
    WHEN apd.OwnerReputationLevel = 'Medium Reputation' AND apd.Score > 50 THEN 'Influential Medium Rep User'
    ELSE 'Standard User Post'
  END AS user_influence_category,
  COALESCE(apd.avg_comment_score, 0) AS non_null_avg_comment_score,
  UPPER(SUBSTRING(apd.OwnerDisplayName FROM 1 FOR 3)) AS name_prefix
FROM AggregatedPostData AS apd
WHERE
  apd.Score > 0 OR apd.ViewCount > 0
UNION
SELECT
  apd.PostId,
  apd.PostTypeId,
  apd.Score,
  apd.AnswerCount,
  apd.FavoriteCount,
  apd.ViewCount,
  apd.OwnerDisplayName,
  apd.OwnerReputationLevel,
  apd.comment_count_per_post,
  apd.avg_comment_score,
  apd.score_vs_type_average,
  apd.post_status_category,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = apd.PostId AND pl.LinkTypeId = 3
  ) AS duplicate_link_count,
  CASE
    WHEN apd.ClosedDate IS NOT NULL THEN EXTRACT(EPOCH FROM (apd.CreationDate - apd.ClosedDate)) / 60
    ELSE NULL
  END AS minutes_open_when_closed,
  CASE
    WHEN apd.OwnerReputationLevel = 'High Reputation' AND apd.Score > 100 THEN 'Influential High Rep User'
    WHEN apd.OwnerReputationLevel = 'Medium Reputation' AND apd.Score > 50 THEN 'Influential Medium Rep User'
    ELSE 'Standard User Post'
  END AS user_influence_category,
  COALESCE(apd.avg_comment_score, 0) AS non_null_avg_comment_score,
  UPPER(SUBSTRING(apd.OwnerDisplayName FROM 1 FOR 3)) AS name_prefix
FROM AggregatedPostData AS apd
WHERE
  apd.Score <= 0 AND apd.ViewCount <= 0 AND apd.FavoriteCount > 0;