-- {"query": "4873.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1916} 

WITH
  PostDetails AS (
    SELECT
      p.Id AS PostId,
      pt.Name AS PostType,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Title,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      CASE
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsCommunityOwned,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNumByUser,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
      SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalScore
    FROM
      Posts AS p
      JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN Users AS u
        ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
  ),
  CommentStats AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCountOnPost,
      SUM(c.Score) AS TotalCommentScore,
      AVG(c.Score) AS AverageCommentScore,
      COUNT(DISTINCT CASE WHEN c.UserId IS NULL THEN NULL ELSE c.UserId END) AS DistinctCommenterCount
    FROM
      Comments AS c
    GROUP BY
      c.PostId
  ),
  VoteDistribution AS (
    SELECT
      v.PostId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id END) AS UpVotes,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id END) AS DownVotes,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN v.Id END) AS Favorites,
      COUNT(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN v.Id END) AS AcceptedAnswers
    FROM
      Votes AS v
      JOIN VoteTypes AS vt
        ON v.VoteTypeId = vt.Id
    GROUP BY
      v.PostId
  ),
  TagFrequency AS (
    SELECT
      t.TagName,
      t.Count AS TagGlobalCount,
      ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM
      Tags AS t
    WHERE
      t.TagName NOT LIKE '%-%' -- Exclude tags with hyphens, often meta-tags
  ),
  UserPostEngagement AS (
    SELECT
      pd.OwnerUserId,
      COUNT(DISTINCT pd.PostId) AS TotalPosts,
      SUM(pd.Score) AS TotalScoreFromPosts,
      AVG(pd.Score) AS AvgScorePerPost,
      MAX(pd.Score) AS MaxScorePost,
      COUNT(CASE WHEN pd.IsClosed = 1 THEN pd.PostId END) AS ClosedPosts,
      COUNT(CASE WHEN pd.IsCommunityOwned = 1 THEN pd.PostId END) AS CommunityOwnedPosts,
      SUM(cs.CommentCountOnPost) AS TotalCommentsMade,
      AVG(cs.AverageCommentScore) AS AvgCommentScoreReceived
    FROM
      PostDetails AS pd
      LEFT JOIN CommentStats AS cs
        ON pd.PostId = cs.PostId
    GROUP BY
      pd.OwnerUserId
    HAVING
      COUNT(DISTINCT pd.PostId) > 5 -- Only consider users with more than 5 posts
  )
SELECT
  pd.PostId,
  pd.PostType,
  pd.OwnerUserId,
  pd.OwnerDisplayName,
  pd.PostCreationDate,
  pd.Title,
  pd.Score,
  pd.ViewCount,
  pd.AnswerCount,
  pd.CommentCount,
  pd.FavoriteCount,
  pd.ClosedDate,
  pd.IsClosed,
  pd.IsCommunityOwned,
  pd.RowNumByUser,
  pd.PreviousPostScore,
  pd.NextPostScore,
  pd.RunningTotalScore,
  cs.CommentCountOnPost,
  cs.TotalCommentScore,
  cs.AverageCommentScore,
  cs.DistinctCommenterCount,
  vd.UpVotes,
  vd.DownVotes,
  vd.Favorites,
  vd.AcceptedAnswers,
  (vd.UpVotes - vd.DownVotes) AS NetVoteScore,
  CASE
    WHEN vd.UpVotes + vd.DownVotes > 0 THEN CAST(vd.UpVotes AS REAL) / (vd.UpVotes + vd.DownVotes)
    ELSE 0
  END AS UpvoteRatio,
  tf.TagName,
  tf.TagRank,
  tf.TagGlobalCount,
  COALESCE(u.Reputation, 0) AS OwnerReputation,
  COALESCE(u.Views, 0) AS OwnerViews,
  COALESCE(u.UpVotes, 0) AS OwnerUpVotes,
  COALESCE(u.DownVotes, 0) AS OwnerDownVotes,
  u.CreationDate AS UserCreationDate,
  STRFTIME('%Y', u.CreationDate) AS UserCreationYear,
  STRFTIME('%m', u.CreationDate) AS UserCreationMonth,
  COALESCE(upe.TotalPosts, 0) AS UserTotalPosts,
  COALESCE(upe.AvgScorePerPost, 0) AS UserAvgScorePerPost,
  COALESCE(upe.ClosedPosts, 0) AS UserClosedPosts,
  REPLACE(REPLACE(REPLACE(SUBSTRING(pd.Title, 1, 50), '>', ''), '<', ''), '&', '') AS CleanedTitle, -- Simple string manipulation
  CASE
    WHEN pd.Score > 100 AND pd.AnswerCount > 10 THEN 'High Engagement'
    WHEN pd.Score < 0 AND pd.ClosedDate IS NOT NULL THEN 'Potentially Problematic'
    ELSE 'Standard'
  END AS PostStatusCategory,
  CASE
    WHEN pd.OwnerUserId = -1 THEN 'Community User'
    WHEN u.Id IS NULL THEN 'Deleted User'
    ELSE COALESCE(u.DisplayName, 'Anonymous')
  END AS EffectiveOwnerDisplayName
FROM
  PostDetails AS pd
  LEFT JOIN CommentStats AS cs
    ON pd.PostId = cs.PostId
  LEFT JOIN VoteDistribution AS vd
    ON pd.PostId = vd.PostId
  LEFT JOIN (
    SELECT DISTINCT -- Select one tag per post for demonstration
      p.Id AS PostId,
      t.TagName,
      t.Count AS TagGlobalCount,
      ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY t.Count DESC) AS rn
    FROM
      Posts AS p
      CROSS JOIN LATERAL (
        SELECT
          TRIM(TAG) AS TagName
        FROM
          STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TAG
      ) AS tags_parsed
      JOIN Tags AS t
        ON tags_parsed.TagName = t.TagName
    WHERE
      p.Tags IS NOT NULL
  ) AS tf
    ON pd.PostId = tf.PostId AND tf.rn = 1
  LEFT JOIN Users AS u
    ON pd.OwnerUserId = u.Id
  LEFT JOIN UserPostEngagement AS upe
    ON pd.OwnerUserId = upe.OwnerUserId
WHERE
  pd.PostCreationDate >= '2023-01-01' -- Filter for recent posts
  AND (
    pd.Title LIKE '%SQL%'
    OR pd.Title LIKE '%Performance%'
  ) -- Search for relevant keywords
ORDER BY
  pd.PostCreationDate DESC,
  pd.Score DESC;
