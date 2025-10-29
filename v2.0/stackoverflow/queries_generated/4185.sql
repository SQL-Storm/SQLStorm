-- {"query": "4185.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2463} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserEditStats AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS distinct_posts_edited,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS title_edits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS body_edits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS tag_edits
    FROM RankedPostEdits AS rpe
    GROUP BY
      rpe.UserId
  ),
  PostEditFrequency AS (
    SELECT
      p.Id AS PostId,
      COUNT(ph.Id) AS edit_count,
      AVG(EXTRACT(EPOCH FROM (p.LastEditDate - p.CreationDate))) AS avg_time_to_first_edit_seconds
    FROM Posts AS p
    JOIN PostHistory AS ph
      ON p.Id = ph.PostId
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      p.Id,
      p.LastEditDate,
      p.CreationDate
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      (
        SELECT
          COUNT(*)
        FROM Comments AS c
        WHERE
          c.UserId = u.Id
      ) AS comment_count,
      (
        SELECT
          COUNT(*)
        FROM Votes AS v
        WHERE
          v.UserId = u.Id AND v.VoteTypeId = 2
      ) AS upvote_count,
      (
        SELECT
          COUNT(*)
        FROM Votes AS v
        WHERE
          v.UserId = u.Id AND v.VoteTypeId = 3
      ) AS downvote_count,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 1
      ) AS gold_badges,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 2
      ) AS silver_badges,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 3
      ) AS bronze_badges
    FROM Users AS u
  )
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  pt.Name AS PostTypeName,
  p.CreationDate AS PostCreationDate,
  p.Score AS PostScore,
  p.ViewCount AS PostViewCount,
  p.AnswerCount,
  p.CommentCount AS PostCommentCount,
  p.FavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  p.OwnerUserId,
  ue.DisplayName AS OwnerDisplayName,
  ue.Reputation AS OwnerReputation,
  ue.comment_count AS OwnerCommentCount,
  ue.upvote_count AS OwnerUpvoteCount,
  ue.downvote_count AS OwnerDownvoteCount,
  ues.distinct_posts_edited AS owner_distinct_posts_edited,
  ues.title_edits AS owner_title_edits,
  ues.body_edits AS owner_body_edits,
  ues.tag_edits AS owner_tag_edits,
  pef.edit_count AS post_edit_count,
  pef.avg_time_to_first_edit_seconds,
  CASE
    WHEN p.Title LIKE '%[a-z]%' AND p.Title LIKE '%[A-Z]%' THEN 'Mixed Case Title'
    WHEN p.Title LIKE '% %' THEN 'Contains Spaces Title'
    ELSE 'Other Title Format'
  END AS title_format_category,
  COALESCE(p.OwnerUserId, -1) AS effective_owner_user_id,
  CASE
    WHEN p.Tags IS NULL THEN 0
    ELSE LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1
  END AS tag_count,
  CASE
    WHEN p.OwnerUserId IS NOT NULL THEN (
      SELECT
        COUNT(*)
      FROM PostHistory AS ph_inner
      WHERE
        ph_inner.PostId = p.Id AND ph_inner.UserId = p.OwnerUserId AND ph_inner.PostHistoryTypeId IN (4, 5, 6)
    )
    ELSE 0
  END AS owner_direct_edits,
  CASE
    WHEN p.AcceptedAnswerId IS NOT NULL THEN (
      SELECT
        COUNT(*)
      FROM Comments AS c_ans
      WHERE
        c_ans.PostId = p.AcceptedAnswerId
    )
    ELSE 0
  END AS accepted_answer_comment_count,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = p.Id AND pl.LinkTypeId = 3
  ) AS duplicate_link_count,
  (
    SELECT
      SUM(c.Score)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id
  ) AS total_comment_score,
  (
    SELECT
      COUNT(DISTINCT ph.UserId)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
  ) AS distinct_editors_count
FROM Posts AS p
LEFT JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN UserEngagement AS ue
  ON p.OwnerUserId = ue.UserId
LEFT JOIN UserEditStats AS ues
  ON p.OwnerUserId = ues.UserId
LEFT JOIN PostEditFrequency AS pef
  ON p.Id = pef.PostId
WHERE
  p.CreationDate >= '2023-01-01' AND p.Score > 5
  AND (p.ViewCount > 1000 OR p.AnswerCount > 10)
  AND EXISTS (
    SELECT
      1
    FROM Comments AS c
    WHERE
      c.PostId = p.Id AND c.CreationDate BETWEEN p.CreationDate AND p.LastActivityDate
  )
  AND p.OwnerUserId IS NOT NULL
UNION
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  pt.Name AS PostTypeName,
  p.CreationDate AS PostCreationDate,
  p.Score AS PostScore,
  p.ViewCount AS PostViewCount,
  p.AnswerCount,
  p.CommentCount AS PostCommentCount,
  p.FavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  p.OwnerUserId,
  ue.DisplayName AS OwnerDisplayName,
  ue.Reputation AS OwnerReputation,
  ue.comment_count AS OwnerCommentCount,
  ue.upvote_count AS OwnerUpvoteCount,
  ue.downvote_count AS OwnerDownvoteCount,
  ues.distinct_posts_edited AS owner_distinct_posts_edited,
  ues.title_edits AS owner_title_edits,
  ues.body_edits AS owner_body_edits,
  ues.tag_edits AS owner_tag_edits,
  pef.edit_count AS post_edit_count,
  pef.avg_time_to_first_edit_seconds,
  CASE
    WHEN p.Title LIKE '%[a-z]%' AND p.Title LIKE '%[A-Z]%' THEN 'Mixed Case Title'
    WHEN p.Title LIKE '% %' THEN 'Contains Spaces Title'
    ELSE 'Other Title Format'
  END AS title_format_category,
  COALESCE(p.OwnerUserId, -1) AS effective_owner_user_id,
  CASE
    WHEN p.Tags IS NULL THEN 0
    ELSE LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1
  END AS tag_count,
  CASE
    WHEN p.OwnerUserId IS NOT NULL THEN (
      SELECT
        COUNT(*)
      FROM PostHistory AS ph_inner
      WHERE
        ph_inner.PostId = p.Id AND ph_inner.UserId = p.OwnerUserId AND ph_inner.PostHistoryTypeId IN (4, 5, 6)
    )
    ELSE 0
  END AS owner_direct_edits,
  CASE
    WHEN p.AcceptedAnswerId IS NOT NULL THEN (
      SELECT
        COUNT(*)
      FROM Comments AS c_ans
      WHERE
        c_ans.PostId = p.AcceptedAnswerId
    )
    ELSE 0
  END AS accepted_answer_comment_count,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = p.Id AND pl.LinkTypeId = 3
  ) AS duplicate_link_count,
  (
    SELECT
      SUM(c.Score)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id
  ) AS total_comment_score,
  (
    SELECT
      COUNT(DISTINCT ph.UserId)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
  ) AS distinct_editors_count
FROM Posts AS p
LEFT JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN UserEngagement AS ue
  ON p.OwnerUserId = ue.UserId
LEFT JOIN UserEditStats AS ues
  ON p.OwnerUserId = ues.UserId
LEFT JOIN PostEditFrequency AS pef
  ON p.Id = pef.PostId
WHERE
  p.ClosedDate IS NOT NULL AND p.Score < -5
  AND p.OwnerUserId IS NULL
ORDER BY
  PostCreationDate DESC
LIMIT 1000;
