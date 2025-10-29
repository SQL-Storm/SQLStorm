-- {"query": "5600.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 898} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.PostTypeId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    COALESCE(uv.Reputation, 0) AS OwnerReputation,
    COALESCE(upv.UpVotes, 0) AS OwnerUpVotes,
    COALESCE(dpv.DownVotes, 0) AS OwnerDownVotes,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn_type
  FROM Posts p
  LEFT JOIN (
    SELECT Id, Reputation, UpVotes, DownVotes
    FROM Users
  ) uv ON uv.Id = p.OwnerUserId
  LEFT JOIN (
    SELECT UserId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes
    FROM Votes
    GROUP BY UserId
  ) upv ON upv.UserId = p.OwnerUserId
  LEFT JOIN (
    SELECT UserId, SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY UserId
  ) dpv ON dpv.UserId = p.OwnerUserId
  WHERE p.PostTypeId IN (1,2,5)
),
activity_clusters AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.OwnerUserId,
    rp.OwnerReputation,
    rp.OwnerUpVotes,
    rp.OwnerDownVotes,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.LastActivityDate,
    CASE
      WHEN rp.LastActivityDate > NOW() - INTERVAL '30 days' THEN 'Recent'
      WHEN rp.LastActivityDate > NOW() - INTERVAL '180 days' THEN 'Moderate'
      ELSE 'Old'
    END AS activity_band
  FROM ranked_posts rp
  WHERE rp.rn_type = 1
),
complex_filters AS (
  SELECT
    ac.Id,
    ac.Title,
    ac.LastActivityDate,
    ac.Activity_band,
    ac.ViewCount,
    ac.Score,
    ac.OwnerUserId,
    ac.OwnerReputation,
    ac.OwnerUpVotes,
    ac.OwnerDownVotes,
    ac.Tags,
    ac.AnswerCount,
    ac.CommentCount,
    -- tricky long-predicate involving tags and numeric expression
    (CASE
       WHEN ac.Tags ~ '\\b(bug|crash|error)\\b' THEN 1
       WHEN ac.Tags ~ '\\b(typescript|javascript|sql)\\b' THEN 2
       ELSE 0
     END
     + (COALESCE(ac.Score,0) * 3)
     - (COALESCE(ac.ViewCount,0) / NULLIF(NULLIF(COALESCE(ac.AnswerCount,0),0),1)
        + CASE WHEN ac.OwnerReputation > 1000 THEN 5 ELSE 0 END)
    ) AS composite_metric
  FROM activity_clusters ac
),
final_selection AS (
  SELECT
    cf.Id,
    cf.Title,
    cf.LastActivityDate,
    cf.Activity_band,
    cf.ViewCount,
    cf.Score,
    cf.OwnerUserId,
    cf.OwnerReputation,
    cf.OwnerUpVotes,
    cf.OwnerDownVotes,
    cf.Tags,
    cf.AnswerCount,
    cf.CommentCount,
    cf.Composite_metric
  FROM complex_filters cf
  ORDER BY
    cf.Composite_metric DESC NULLS LAST,
    cf.LastActivityDate DESC,
    cf.Score DESC
  LIMIT 500
)
SELECT
  fs.Id AS PostId,
  fs.Title,
  fs.LastActivityDate,
  fs.Activity_band,
  fs.ViewCount,
  fs.Score,
  fs.OwnerUserId,
  fs.OwnerReputation,
  fs.OwnerUpVotes,
  fs.OwnerDownVotes,
  fs.Tags,
  fs.AnswerCount,
  fs.CommentCount
FROM final_selection fs
;