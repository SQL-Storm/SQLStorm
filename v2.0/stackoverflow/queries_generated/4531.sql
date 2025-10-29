-- {"query": "4531.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1158} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.UserId,
      ph.Comment,
      pht.Name AS HistoryTypeName,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserPostInteraction AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserName,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
      SUM(p.Score) AS TotalScoreReceived,
      COUNT(DISTINCT c.Id) AS TotalCommentsMade,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c
      ON u.Id = c.UserId
    LEFT JOIN Votes v
      ON u.Id = v.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  PostQuality AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      CASE
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsCommunityOwned,
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM PostLinks pl
          WHERE
            pl.PostId = p.Id AND pl.LinkTypeId = 3
        ) THEN 1
        ELSE 0
      END AS IsLinkedAsDuplicate,
      p.AnswerCount * 1.0 / NULLIF(p.CommentCount, 0) AS AnswerCommentRatio,
      p.FavoriteCount * 1.0 / NULLIF(p.ViewCount, 0) AS FavoriteViewRatio,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0 AND p.PostTypeId IN (1, 2) -- Questions and Answers
  )
SELECT
  pq.PostId,
  pq.Title,
  pq.PostTypeName,
  pq.OwnerUserId,
  ui.UserName,
  pq.CreationDate,
  pq.Score,
  pq.ViewCount,
  pq.AnswerCount,
  pq.CommentCount,
  pq.FavoriteCount,
  pq.IsClosed,
  pq.IsCommunityOwned,
  pq.IsLinkedAsDuplicate,
  pq.AnswerCommentRatio,
  pq.FavoriteViewRatio,
  rpe.HistoryTypeName AS LastEditType,
  rpe.CreationDate AS LastEditDate,
  rpe.UserId AS LastEditorUserId,
  rpe.Comment AS LastEditComment,
  ui.TotalPostsOwned,
  ui.QuestionsOwned,
  ui.AnswersOwned,
  ui.TotalScoreReceived,
  ui.TotalCommentsMade,
  ui.TotalUpvotesGiven,
  ui.TotalDownvotesGiven,
  pq.PreviousPostScore
FROM PostQuality pq
JOIN UserPostInteraction ui
  ON pq.OwnerUserId = ui.UserId
LEFT JOIN RankedPostEdits rpe
  ON pq.PostId = rpe.PostId AND rpe.rn = 1
WHERE
  pq.Score > 100 -- Focusing on posts with some traction
  AND ui.TotalPostsOwned > 50 -- Focusing on users with significant contribution
  AND pq.ViewCount > 1000
  AND (
    pq.AnswerCommentRatio > 0.5 OR pq.FavoriteViewRatio > 0.001
  )
  AND LOWER(pq.Title) LIKE '%sql%'
  AND COALESCE(pq.LastEditComment, '') != 'minor correction'
ORDER BY
  pq.Score DESC,
  pq.ViewCount DESC;
