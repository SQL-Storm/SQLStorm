-- {"query": "4906.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1833} 

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
      Posts AS p
      LEFT JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN Users AS u
        ON p.OwnerUserId = u.Id
      LEFT JOIN Comments AS c
        ON p.Id = c.PostId
      LEFT JOIN Votes AS v
        ON p.Id = v.PostId
      LEFT JOIN PostHistory AS ph
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
      SUM(CASE WHEN PostTypeId = 'Question' THEN 1 ELSE 0 END) AS TotalUserQuestions,
      SUM(CASE WHEN PostTypeId = 'Answer' THEN 1 ELSE 0 END) AS TotalUserAnswers,
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
      p.Id AS PostId,
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
      Posts AS pf
      JOIN Tags AS t
        ON pf.Tags LIKE '%' || t.TagName || '%' -- Inefficient for large number of tags
      LEFT JOIN PostTypes AS pt
        ON pf.PostTypeId = pt.Id
    WHERE
      pf.PostTypeId IN (1, 2) -- Questions and Answers
      AND t.TagName NOT IN ('sql', 'performance', 'query', 'database') -- Exclude meta tags
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
  CONCAT(
    COALESCE(pi.OwnerDisplayName, 'Anonymous'),
    ' | ',
    CAST(pi.PostScore AS VARCHAR),
    ' | ',
    DATE_TRUNC('day', pi.PostCreationDate)
  ) AS PostSummary,
  (
    SELECT
      COUNT(sub_c.Id)
    FROM
      Comments AS sub_c
    WHERE
      sub_c.PostId = pi.PostId
      AND sub_c.UserId IS NOT NULL
      AND sub_c.Score > 0
  ) AS PositiveCommentCount,
  EXISTS (
    SELECT
      1
    FROM
      PostLinks AS pl
    WHERE
      pl.PostId = pi.PostId AND pl.LinkTypeId = 3 -- Duplicate Link
  ) AS IsDuplicateLink,
  GREATEST(
    pi.PostCreationDate,
    COALESCE(pi.LastCommentDate, '1970-01-01')
  ) AS LastInteractionDate
FROM
  PostInteractions AS pi
LEFT JOIN
  UserActivitySummary AS ua
    ON pi.OwnerUserId = ua.OwnerUserId
LEFT JOIN
  TagPerformance AS tp
    ON pi.PostId = tp.PostId
WHERE
  pi.PostNumberForOwner <= 10 -- Consider only the 10 most recent posts for each owner
  AND pi.PostScore > 5 -- Filter for posts with a decent score
  AND tp.RankByScore <= 5 -- Consider top 5 performing posts within a tag
ORDER BY
  pi.PostCreationDate DESC
FETCH FIRST 1000 ROWS ONLY;
