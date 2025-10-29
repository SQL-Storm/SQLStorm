WITH
  PostInteractions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount,
      COUNT(DISTINCT ph.Id) AS PostHistoryCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteCount,
      AVG(c.Score) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostNumberForOwner
    FROM
      Posts p
      LEFT JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN Users u
        ON p.OwnerUserId = u.Id
      LEFT JOIN Comments c
        ON p.Id = c.PostId
      LEFT JOIN Votes v
        ON p.Id = v.PostId
      LEFT JOIN PostHistory ph
        ON p.Id = ph.PostId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name,
      u.DisplayName,
      u.Reputation
  ),
  UserActivitySummary AS (
    SELECT
      OwnerUserId,
      SUM(PostScore) AS TotalUserPostScore,
      AVG(PostScore) AS AvgUserPostScore,
      SUM(PostViewCount) AS TotalUserPostViews,
      AVG(PostViewCount) AS AvgUserPostViews,
      COUNT(PostId) AS TotalUserPosts,
      SUM(CASE WHEN PostTypeName = 'Question' THEN 1 ELSE 0 END) AS TotalUserQuestions,
      SUM(CASE WHEN PostTypeName = 'Answer' THEN 1 ELSE 0 END) AS TotalUserAnswers,
      MAX(PostCreationDate) AS LatestPostDate,
      MIN(PostCreationDate) AS EarliestPostDate,
      COUNT(DISTINCT ClosedDate) AS ClosedPostCount,
      SUM(UpVoteCount) AS TotalUpVotesReceived,
      SUM(DownVoteCount) AS TotalDownVotesReceived,
      SUM(FavoriteVoteCount) AS TotalFavoriteVotesReceived
    FROM
      PostInteractions
    GROUP BY
      OwnerUserId
  ),
  TagPerformance AS (
    SELECT
      pf.Id AS PostId,
      t.TagName,
      CASE
        WHEN pf.PostTypeId = 1 THEN 'Question'
        WHEN pf.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
      END AS PostType,
      pf.Score AS PostScore,
      pf.ViewCount AS PostViewCount,
      pf.AnswerCount AS PostAnswerCount,
      pf.CommentCount AS PostCommentCount,
      pf.FavoriteCount AS PostFavoriteCount,
      ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY pf.Score DESC) AS RankByScore,
      AVG(pf.Score) OVER (PARTITION BY t.TagName) AS AvgScoreInTag,
      SUM(pf.Score) OVER (PARTITION BY t.TagName) AS SumScoreInTag
    FROM
      Posts pf
      JOIN Tags t
        ON pf.Tags LIKE '%' || t.TagName || '%'
      LEFT JOIN PostTypes pt
        ON pf.PostTypeId = pt.Id
    WHERE
      pf.PostTypeId IN (1, 2)
      AND t.TagName NOT IN ('sql', 'performance', 'query', 'database')
  )
SELECT
  pi.PostId,
  pi.PostTypeName,
  pi.PostCreationDate,
  pi.PostScore,
  pi.PostViewCount,
  pi.PostAnswerCount,
  pi.PostCommentCount,
  pi.PostFavoriteCount,
  pi.OwnerDisplayName,
  pi.OwnerReputation,
  pi.CommentCount AS ActualCommentCount,
  pi.VoteCount,
  pi.PostHistoryCount,
  pi.UpVoteCount,
  pi.DownVoteCount,
  pi.FavoriteVoteCount,
  pi.AvgCommentScore,
  pi.LastCommentDate,
  ua.TotalUserPostScore,
  ua.AvgUserPostScore,
  ua.TotalUserPostViews,
  ua.AvgUserPostViews,
  ua.TotalUserPosts,
  ua.TotalUserQuestions,
  ua.TotalUserAnswers,
  ua.LatestPostDate,
  ua.EarliestPostDate,
  ua.ClosedPostCount,
  ua.TotalUpVotesReceived,
  ua.TotalDownVotesReceived,
  ua.TotalFavoriteVotesReceived,
  tp.TagName,
  tp.RankByScore,
  tp.AvgScoreInTag,
  tp.SumScoreInTag,
  CASE
    WHEN pi.PostScore > ua.AvgUserPostScore THEN 'Above Average User Score'
    WHEN pi.PostScore < ua.AvgUserPostScore THEN 'Below Average User Score'
    ELSE 'Average User Score'
  END AS ScoreComparison,
  CASE
    WHEN pi.PostFavoriteCount > 0 AND pi.ClosedDate IS NOT NULL THEN 'Popular Closed Post'
    WHEN pi.PostFavoriteCount > 100 THEN 'Highly Favorited Post'
    ELSE 'Standard Post'
  END AS PostCategorization,
  (COALESCE(pi.OwnerDisplayName, 'Anonymous') || ' | ' || CAST(pi.PostScore AS VARCHAR) || ' | ' || DATE_TRUNC('day', pi.PostCreationDate)) AS PostSummary,
  (
    SELECT
      COUNT(sub_c.Id)
    FROM
      Comments sub_c
    WHERE
      sub_c.PostId = pi.PostId
      AND sub_c.UserId IS NOT NULL
      AND sub_c.Score > 0
  ) AS PositiveCommentCount,
  EXISTS (
    SELECT
      1
    FROM
      PostLinks pl
    WHERE
      pl.PostId = pi.PostId AND pl.LinkTypeId = 3
  ) AS IsDuplicateLink,
  GREATEST(
    pi.PostCreationDate,
    COALESCE(pi.LastCommentDate, DATE '1970-01-01')
  ) AS LastInteractionDate
FROM
  PostInteractions pi
LEFT JOIN
  UserActivitySummary ua
    ON pi.OwnerUserId = ua.OwnerUserId
LEFT JOIN
  TagPerformance tp
    ON pi.PostId = tp.PostId
WHERE
  pi.PostNumberForOwner <= 10
  AND pi.PostScore > 5
  AND (tp.RankByScore IS NULL OR tp.RankByScore <= 5)
ORDER BY
  pi.PostCreationDate DESC
FETCH FIRST 1000 ROWS ONLY;