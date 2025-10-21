-- {"query": "48068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1560} 

WITH
  RelevantPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      u.Reputation AS OwnerReputation,
      u.Views AS OwnerViews,
      u.UpVotes AS OwnerUpVotes,
      u.DownVotes AS OwnerDownVotes,
      (
        SELECT
          COUNT(*)
        FROM
          Comments c
        WHERE
          c.PostId = p.Id
      ) AS ActualCommentCount,
      (
        SELECT
          COUNT(*)
        FROM
          PostHistory ph
        WHERE
          ph.PostId = p.Id
      ) AS PostHistoryCount,
      (
        SELECT
          COUNT(*)
        FROM
          PostLinks pl
        WHERE
          pl.PostId = p.Id OR pl.RelatedPostId = p.Id
      ) AS PostLinkCount
    FROM
      Posts p
      JOIN PostTypes pt ON p.PostTypeId = pt.Id
      LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2) AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  ),
  UserPostActivity AS (
    SELECT
      rp.OwnerUserId,
      COUNT(rp.PostId) AS TotalPosts,
      SUM(rp.PostScore) AS TotalScore,
      SUM(rp.PostViewCount) AS TotalViews,
      AVG(rp.OwnerReputation) AS AvgOwnerReputation,
      AVG(rp.OwnerViews) AS AvgOwnerViews,
      AVG(rp.OwnerUpVotes) AS AvgOwnerUpVotes,
      AVG(rp.OwnerDownVotes) AS AvgOwnerDownVotes,
      SUM(rp.ActualCommentCount) AS TotalCommentsReceived,
      SUM(rp.PostHistoryCount) AS TotalPostHistoryEntries,
      SUM(rp.PostLinkCount) AS TotalPostLinks
    FROM
      RelevantPosts rp
    WHERE
      rp.OwnerUserId IS NOT NULL
    GROUP BY
      rp.OwnerUserId
  ),
  PostMetrics AS (
    SELECT
      rp.PostId,
      rp.PostTypeId,
      rp.PostTypeName,
      rp.OwnerUserId,
      rp.PostCreationDate,
      rp.PostScore,
      rp.PostViewCount,
      rp.AnswerCount,
      rp.CommentCount,
      rp.FavoriteCount,
      CASE WHEN rp.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      upa.TotalPosts AS UserTotalPosts,
      upa.TotalScore AS UserTotalScore,
      upa.TotalViews AS UserTotalViews,
      upa.AvgOwnerReputation,
      upa.AvgOwnerViews,
      upa.AvgOwnerUpVotes,
      upa.AvgOwnerDownVotes,
      rp.ActualCommentCount,
      rp.PostHistoryCount,
      rp.PostLinkCount,
      ROW_NUMBER() OVER (ORDER BY rp.PostScore DESC, rp.PostViewCount DESC) AS ScoreRank,
      ROW_NUMBER() OVER (ORDER BY rp.PostViewCount DESC) AS ViewCountRank,
      ROW_NUMBER() OVER (ORDER BY rp.FavoriteCount DESC) AS FavoriteCountRank,
      ROW_NUMBER() OVER (PARTITION BY rp.PostTypeId ORDER BY rp.PostScore DESC) AS PostTypeScoreRank,
      ROW_NUMBER() OVER (PARTITION BY rp.PostTypeId ORDER BY rp.PostViewCount DESC) AS PostTypeViewCountRank
    FROM
      RelevantPosts rp
      LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.OwnerUserId
  )
SELECT
  pm.PostId,
  pm.PostTypeName,
  pm.PostCreationDate,
  pm.PostScore,
  pm.PostViewCount,
  pm.AnswerCount,
  pm.CommentCount,
  pm.FavoriteCount,
  pm.IsClosed,
  pm.UserTotalPosts,
  pm.UserTotalScore,
  pm.UserTotalViews,
  pm.AvgOwnerReputation,
  pm.AvgOwnerViews,
  pm.AvgOwnerUpVotes,
  pm.AvgOwnerDownVotes,
  pm.ActualCommentCount,
  pm.PostHistoryCount,
  pm.PostLinkCount,
  pm.ScoreRank,
  pm.ViewCountRank,
  pm.FavoriteCountRank,
  pm.PostTypeScoreRank,
  pm.PostTypeViewCountRank,
  CASE
    WHEN pm.PostViewCount > 0 THEN CAST(pm.PostScore AS REAL) / pm.PostViewCount
    ELSE 0
  END AS ScorePerView,
  CASE
    WHEN pm.UserTotalPosts > 0 THEN CAST(pm.PostScore AS REAL) / pm.UserTotalPosts
    ELSE 0
  END AS ScorePerUserPost,
  CASE
    WHEN pm.ActualCommentCount > 0 THEN CAST(pm.PostScore AS REAL) / pm.ActualCommentCount
    ELSE 0
  END AS ScorePerComment,
  CASE
    WHEN pm.PostHistoryCount > 0 THEN CAST(pm.PostScore AS REAL) / pm.PostHistoryCount
    ELSE 0
  END AS ScorePerHistoryEntry,
  CASE
    WHEN pm.FavoriteCount > 0 THEN CAST(pm.PostViewCount AS REAL) / pm.FavoriteCount
    ELSE 0
  END AS ViewsPerFavorite,
  (
    SELECT
      COUNT(*)
    FROM
      Votes v
    WHERE
      v.PostId = pm.PostId AND v.VoteTypeId = 2 /* UpVote */
  ) AS UpVoteCount,
  (
    SELECT
      COUNT(*)
    FROM
      Votes v
    WHERE
      v.PostId = pm.PostId AND v.VoteTypeId = 3 /* DownVote */
  ) AS DownVoteCount,
  (
    SELECT
      COUNT(*)
    FROM
      Comments c
    WHERE
      c.PostId = pm.PostId AND c.Score > 0
  ) AS PositiveCommentCount,
  (
    SELECT
      COUNT(*)
    FROM
      PostHistory ph
    WHERE
      ph.PostId = pm.PostId AND ph.PostHistoryTypeId IN (4, 5, 6) /* Edits */
  ) AS EditCount
FROM
  PostMetrics pm
ORDER BY
  pm.PostScore DESC,
  pm.PostViewCount DESC
LIMIT 1000;
