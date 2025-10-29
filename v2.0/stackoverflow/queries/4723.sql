-- {"query": "4723.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1446}
WITH
  RelevantPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      CASE
        WHEN p.PostTypeId = 1 THEN p.Title
        ELSE NULL
      END AS QuestionTitle,
      CASE
        WHEN p.PostTypeId = 2 THEN (
          SELECT p2.Title FROM Posts p2 WHERE p2.Id = p.ParentId
        )
        ELSE NULL
      END AS ParentQuestionTitle,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
      p.Tags
    FROM
      Posts p
      JOIN PostTypes pt ON p.PostTypeId = pt.Id
      LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      p.CreationDate > DATE '2023-01-01' AND p.Score > 0
  ),
  PostComments AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS NumberOfComments,
      AVG(c.Score) AS AverageCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM
      Comments c
    GROUP BY
      c.PostId
  ),
  TagInfo AS (
    SELECT
      t.TagName,
      COUNT(p.Id) AS TagPostCount,
      SUM(p.Score) AS TotalTagScore
    FROM
      Tags t
      JOIN Posts p
        ON POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    WHERE
      p.PostTypeId = 1
    GROUP BY
      t.TagName
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT ph.PostId) AS PostsEdited,
      SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
      MAX(ph.CreationDate) AS LastEditDate
    FROM
      Users u
      JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE
      ph.CreationDate > DATE '2023-01-01'
    GROUP BY
      u.Id
  )
SELECT
  rp.PostId,
  rp.PostTypeName,
  rp.OwnerDisplayName,
  rp.PostCreationDate,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.ViewCount,
  rp.QuestionTitle,
  rp.ParentQuestionTitle,
  COALESCE(pc.NumberOfComments, 0) AS TotalComments,
  COALESCE(pc.AverageCommentScore, 0) AS AvgCommentScore,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  ua.PostsEdited AS UserTotalEdits,
  ua.BodyEdits AS UserBodyEdits,
  ti.TagName,
  ti.TagPostCount,
  ti.TotalTagScore,
  rp.UserPostRank,
  ('User: ' || COALESCE(rp.OwnerDisplayName, '') || ' | PostType: ' || rp.PostTypeName || ' | Score: ' || CAST(rp.Score AS VARCHAR)) AS SearchKey
FROM
  RelevantPosts rp
  LEFT JOIN PostComments pc ON rp.PostId = pc.PostId
  LEFT JOIN TagInfo ti
    ON POSITION('<' || ti.TagName || '>' IN rp.Tags) > 0
    AND rp.PostTypeId = 1
  LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE
  (
    rp.Score > 5
    AND (
      rp.OwnerDisplayName LIKE '%a%'
      OR rp.OwnerDisplayName IS NULL
    )
    AND rp.UserPostRank <= 10
    AND rp.FavoriteCount > 0
  )
  OR rp.CommentCount > 10
UNION ALL
SELECT
  rp.PostId,
  rp.PostTypeName,
  rp.OwnerDisplayName,
  rp.PostCreationDate,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.ViewCount,
  rp.QuestionTitle,
  rp.ParentQuestionTitle,
  COALESCE(pc.NumberOfComments, 0) AS TotalComments,
  COALESCE(pc.AverageCommentScore, 0) AS AvgCommentScore,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  ua.PostsEdited AS UserTotalEdits,
  ua.BodyEdits AS UserBodyEdits,
  ti.TagName,
  ti.TagPostCount,
  ti.TotalTagScore,
  rp.UserPostRank,
  ('User: ' || COALESCE(rp.OwnerDisplayName, '') || ' | PostType: ' || rp.PostTypeName || ' | Score: ' || CAST(rp.Score AS VARCHAR)) AS SearchKey
FROM
  RelevantPosts rp
  LEFT JOIN PostComments pc ON rp.PostId = pc.PostId
  LEFT JOIN TagInfo ti
    ON POSITION('<' || ti.TagName || '>' IN rp.Tags) > 0
    AND rp.PostTypeId = 1
  LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE
  rp.Score < -5
  AND ua.UserId IS NULL
ORDER BY
  PostCreationDate DESC;