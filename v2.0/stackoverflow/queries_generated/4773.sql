-- {"query": "4773.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1334} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.UserId,
      ph.Comment,
      ph.Text,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  LatestPostEdits AS (
    SELECT
      rph.PostId,
      rph.UserId AS LastEditorUserId,
      rph.CreationDate AS LastEditDate,
      (
        CASE WHEN rph.PostHistoryTypeId = 4 THEN rph.Text ELSE NULL END
      ) AS EditedTitle,
      (
        CASE WHEN rph.PostHistoryTypeId = 5 THEN rph.Text ELSE NULL END
      ) AS EditedBody,
      (
        CASE WHEN rph.PostHistoryTypeId = 6 THEN rph.Text ELSE NULL END
      ) AS EditedTags
    FROM RankedPostHistory AS rph
    WHERE
      rph.rn = 1
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPostsOwned,
      SUM(p.Score) AS TotalScoreOwned,
      AVG(p.AnswerCount) AS AvgAnswerCountOwned
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentActivity AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalCommentsMade,
      SUM(c.Score) AS TotalCommentScore
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL AND c.UserId > 0
    GROUP BY
      c.UserId
  ),
  UserVoteActivity AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
    FROM Votes AS v
    WHERE
      v.UserId IS NOT NULL AND v.UserId > 0
    GROUP BY
      v.UserId
  )
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  p.CreationDate AS PostCreationDate,
  p.Score AS PostScore,
  p.ViewCount AS PostViewCount,
  p.AnswerCount AS PostAnswerCount,
  p.CommentCount AS PostCommentCount,
  p.FavoriteCount AS PostFavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  u.CreationDate AS OwnerCreationDate,
  lp.LastEditorUserId,
  lp.LastEditDate,
  lp.EditedTitle,
  lp.EditedBody,
  lp.EditedTags,
  up.TotalPostsOwned,
  up.TotalScoreOwned,
  up.AvgAnswerCountOwned,
  uc.TotalCommentsMade,
  uc.TotalCommentScore,
  uv.UpVotesGiven,
  uv.DownVotesGiven,
  CASE
    WHEN p.OwnerUserId IS NULL THEN 'Community Owned'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'User Owned'
  END AS OwnershipStatus,
  COALESCE(p.OwnerUserId, -1) AS OwnerIdOrSentinel,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.Id IN (SELECT PostId FROM PostLinks WHERE LinkTypeId = 3) THEN 'Linked as Duplicate'
    ELSE 'Open'
  END AS PostStatus,
  LENGTH(p.Body) AS BodyLength,
  UPPER(SUBSTRING(p.Title FROM 1 FOR 3)) AS TitlePrefix,
  CASE
    WHEN lp.LastEditorUserId IS NOT NULL AND lp.LastEditDate > p.CreationDate THEN 'Edited'
    ELSE 'Not Edited'
  END AS EditStatus,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id AND c.Score > 0
  ) AS PositiveCommentCount,
  (
    SELECT
      SUM(v.BountyAmount)
    FROM Votes AS v
    WHERE
      v.PostId = p.Id AND v.VoteTypeId = 8 -- BountyStart
  ) AS TotalBountyAmount,
  COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS InteractionCount
FROM Posts AS p
LEFT OUTER JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT OUTER JOIN Users AS u
  ON p.OwnerUserId = u.Id
LEFT OUTER JOIN LatestPostEdits AS lp
  ON p.Id = lp.PostId
LEFT OUTER JOIN UserPostActivity AS up
  ON p.OwnerUserId = up.OwnerUserId
LEFT OUTER JOIN UserCommentActivity AS uc
  ON p.OwnerUserId = uc.UserId
LEFT OUTER JOIN UserVoteActivity AS uv
  ON p.OwnerUserId = uv.UserId
WHERE
  p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND (
    p.Score > 10 OR p.ViewCount > 1000
  )
  AND p.Title IS NOT NULL
  AND UPPER(p.Title) LIKE '%SQL%'
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;
