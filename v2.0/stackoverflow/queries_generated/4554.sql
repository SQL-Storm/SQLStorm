-- {"query": "4554.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2324} 

WITH
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.FavoriteCount AS PostFavoriteCount,
      p.ViewCount AS PostViewCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      pt.Name AS PostTypeName,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      COALESCE(v.TotalUpVotes, 0) AS TotalPostUpVotes,
      COALESCE(c.TotalComments, 0) AS TotalPostComments,
      COALESCE(a.TotalAnswers, 0) AS TotalPostAnswers,
      COALESCE(f.TotalFavorites, 0) AS TotalPostFavorites,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    LEFT JOIN (
      SELECT
        PostId,
        COUNT(*) AS TotalUpVotes
      FROM Votes
      WHERE
        VoteTypeId = 2
      GROUP BY
        PostId
    ) AS v
      ON p.Id = v.PostId
    LEFT JOIN (
      SELECT
        PostId,
        COUNT(*) AS TotalComments
      FROM Comments
      GROUP BY
        PostId
    ) AS c
      ON p.Id = c.PostId
    LEFT JOIN (
      SELECT
        ParentId AS PostId,
        COUNT(*) AS TotalAnswers
      FROM Posts
      WHERE
        PostTypeId = 2
      GROUP BY
        ParentId
    ) AS a
      ON p.Id = a.PostId
    LEFT JOIN (
      SELECT
        PostId,
        COUNT(*) AS TotalFavorites
      FROM Votes
      WHERE
        VoteTypeId = 5
      GROUP BY
        PostId
    ) AS f
      ON p.Id = f.PostId
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(DISTINCT Id) AS TotalPosts,
      SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
      SUM(PostScore) AS TotalScoreReceived,
      AVG(PostScore) AS AvgPostScore,
      SUM(PostViewCount) AS TotalViewsReceived,
      AVG(PostViewCount) AS AvgPostViewCount,
      MAX(PostCreationDate) AS LatestPostDate
    FROM PostEngagement
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      UserId
  ),
  TagPerformance AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS TotalPostsWithTag,
      SUM(p.Score) AS TotalScoreForTag,
      AVG(CAST(p.Score AS DECIMAL(10, 2))) AS AvgScoreForTag,
      SUM(p.ViewCount) AS TotalViewsForTag,
      AVG(CAST(p.ViewCount AS DECIMAL(10, 2))) AS AvgViewCountForTag,
      SUM(p.AnswerCount) AS TotalAnswersForTag,
      AVG(CAST(p.AnswerCount AS DECIMAL(10, 2))) AS AvgAnswerCountForTag
    FROM Posts AS p
    CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '') AS s -- Assuming a simpler tag splitting for demonstration
    JOIN Tags AS t
      ON s.value = t.TagName
    WHERE
      p.PostTypeId = 1
    GROUP BY
      t.TagName
  ),
  TopUsers AS (
    SELECT
      UserId,
      DisplayName,
      Reputation,
      CreationDate,
      ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
    WHERE
      Id > 0 -- Exclude community user
  ),
  CloseVotesSummary AS (
    SELECT
      PostId,
      COUNT(CASE WHEN VoteTypeId = 6 THEN 1 ELSE NULL END) AS TotalCloseVotes,
      COUNT(CASE WHEN VoteTypeId = 7 THEN 1 ELSE NULL END) AS TotalReopenVotes
    FROM Votes
    WHERE
      VoteTypeId IN (6, 7)
    GROUP BY
      PostId
  )
SELECT
  pe.PostId,
  pe.PostTypeName,
  pe.PostCreationDate,
  pe.PostScore,
  pe.PostFavoriteCount,
  pe.PostViewCount,
  pe.PostCommentCount,
  pe.OwnerDisplayName,
  pe.OwnerReputation,
  pe.TotalPostUpVotes,
  pe.TotalPostComments,
  pe.TotalPostAnswers,
  pe.TotalPostFavorites,
  COALESCE(tu.DisplayName, 'Unknown') AS TopOwnerDisplayName,
  COALESCE(tu.Reputation, 0) AS TopOwnerReputation,
  COALESCE(cvs.TotalCloseVotes, 0) AS NumberOfCloseVotes,
  COALESCE(cvs.TotalReopenVotes, 0) AS NumberOfReopenVotes,
  CASE
    WHEN pe.PostFavoriteCount > 100 AND pe.PostScore > 50 THEN 'Highly Favorited and Scored'
    WHEN pe.PostAnswerCount > 20 OR pe.PostCommentCount > 50 THEN 'Highly Engaged'
    WHEN pe.PostViewCount > 10000 THEN 'High Traffic'
    WHEN pe.PostTypeId = 1 AND pe.PostScore < 0 THEN 'Negatively Scored Question'
    WHEN pe.PostTypeId = 2 AND pe.PostScore < 0 THEN 'Negatively Scored Answer'
    ELSE 'Standard Engagement'
  END AS EngagementCategory,
  DATEDIFF(day, pe.PostCreationDate, GETDATE()) AS DaysSinceCreation,
  CONCAT(pe.OwnerDisplayName, ' (Rep: ', pe.OwnerReputation, ')') AS OwnerInfo,
  CASE
    WHEN UPPER(pe.PostTypeName) LIKE '%WIKI%' THEN 'Community Wiki'
    ELSE 'User Contributed'
  END AS ContentType,
  tp.TagName,
  tp.TotalPostsWithTag,
  tp.TotalScoreForTag,
  tp.AvgScoreForTag,
  tp.TotalViewsForTag,
  tp.AvgViewCountForTag,
  tp.TotalAnswersForTag,
  tp.AvgAnswerCountForTag,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = pe.PostId AND c.UserId = pe.OwnerUserId
  ) AS OwnerCommentsOnOwnPost,
  COALESCE(
    (
      SELECT
        SUM(ph.Id) -- Arbitrary aggregate on PostHistory ID to simulate complex subquery
      FROM PostHistory AS ph
      WHERE
        ph.PostId = pe.PostId AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edits
    ),
    0
  ) AS TotalEditsOnPost,
  CASE
    WHEN pe.OwnerReputation >= 100000 THEN 'High Reputation Owner'
    WHEN pe.OwnerReputation BETWEEN 10000 AND 99999 THEN 'Medium Reputation Owner'
    ELSE 'Low Reputation Owner'
  END AS OwnerReputationTier,
  IIF(pe.PostTypeName = 'Question', pe.PostScore + (pe.PostFavoriteCount * 5), pe.PostScore) AS WeightedScore -- Simple weighted score
FROM PostEngagement AS pe
LEFT JOIN TopUsers AS tu
  ON pe.OwnerUserId = tu.UserId AND tu.Rank <= 10 -- Top 10 users by reputation
LEFT JOIN CloseVotesSummary AS cvs
  ON pe.PostId = cvs.PostId
LEFT JOIN TagPerformance AS tp
  ON pe.PostId IN (
    SELECT
      p.Id
    FROM Posts AS p
    CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '') AS s
    WHERE
      s.value = tp.TagName
  ) -- Join for posts associated with a tag
WHERE
  pe.PostTypeId = 1 -- Focus on Questions for this part of the analysis
  AND pe.PostCreationDate >= DATEADD(year, -1, GETDATE())
  AND pe.PostScore > 0
  AND pe.OwnerReputation IS NOT NULL
  AND pe.OwnerDisplayName IS NOT NULL
  AND pe.OwnerDisplayName NOT LIKE '%[0-9]%' -- Exclude users with numbers in their display name
  AND pe.PostTypeName <> 'TagWikiExcerpt' -- Exclude specific post types
GROUP BY
  pe.PostId,
  pe.PostTypeName,
  pe.PostCreationDate,
  pe.PostScore,
  pe.PostFavoriteCount,
  pe.PostViewCount,
  pe.PostCommentCount,
  pe.OwnerDisplayName,
  pe.OwnerReputation,
  pe.TotalPostUpVotes,
  pe.TotalPostComments,
  pe.TotalPostAnswers,
  pe.TotalPostFavorites,
  tu.DisplayName,
  tu.Reputation,
  cvs.TotalCloseVotes,
  cvs.TotalReopenVotes,
  tp.TagName,
  tp.TotalPostsWithTag,
  tp.TotalScoreForTag,
  tp.AvgScoreForTag,
  tp.TotalViewsForTag,
  tp.AvgViewCountForTag,
  tp.TotalAnswersForTag,
  tp.AvgAnswerCountForTag
HAVING
  COUNT(pe.PostId) > 1 -- Ensure multiple entries if joined via TagPerformance
ORDER BY
  pe.PostCreationDate DESC
LIMIT 100; -- Limit the output for benchmarking purposes
