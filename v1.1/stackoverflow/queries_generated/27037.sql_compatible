WITH
  ActiveUsers AS (
    SELECT
      Id,
      Reputation,
      CreationDate,
      DisplayName,
      LastAccessDate,
      UpVotes,
      DownVotes,
      Views,
      DENSE_RANK() OVER (ORDER BY Reputation DESC, UpVotes DESC, DownVotes ASC) AS ReputationRank
    FROM
      Users
    WHERE
      LastAccessDate >= (CAST('2024-10-01' AS date) - INTERVAL '6' MONTH)
  ),
  RecentPosts AS (
    SELECT
      P.Id AS PostId,
      P.PostTypeId,
      P.CreationDate,
      P.Score,
      P.ViewCount,
      P.AnswerCount,
      P.Title,
      P.Body,
      P.OwnerUserId,
      U.DisplayName AS OwnerDisplayName,
      LAST_VALUE(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS LastPostScore,
      ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS PostRank
    FROM
      Posts P
      LEFT JOIN ActiveUsers U ON P.OwnerUserId = U.Id
    WHERE
      P.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '3' MONTH)
        AND P.PostTypeId IN (1, 2)
  ),
  HighActivityPosts AS (
    SELECT
      PostId,
      PostTypeId,
      CreationDate,
      Score,
      ViewCount,
      AnswerCount,
      Title,
      OwnerUserId,
      OwnerDisplayName,
      LastPostScore,
      PostRank
    FROM
      RecentPosts
    WHERE
      (Score > 10 AND ViewCount > 500) OR
      (AnswerCount > 5 AND ViewCount > 300)
  ),
  RecentComments AS (
    SELECT
      C.Id AS CommentId,
      C.PostId,
      C.Score AS CommentScore,
      C.Text,
      C.CreationDate AS CommentCreationDate,
      C.UserId AS CommentUserId,
      U.DisplayName AS CommentUserDisplayName,
      ROW_NUMBER() OVER (PARTITION BY C.PostId ORDER BY C.CreationDate DESC) AS CommentRank
    FROM
      Comments C
      LEFT JOIN ActiveUsers U ON C.UserId = U.Id
    WHERE
      C.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '3' MONTH)
  ),
  TopTags AS (
    SELECT
      T.Id AS TagId,
      T.TagName,
      T.Count,
      T.ExcerptPostId,
      T.WikiPostId,
      (EXTRACT(YEAR FROM CAST('2024-10-01' AS date)) * 12 + EXTRACT(MONTH FROM CAST('2024-10-01' AS date))
       - (EXTRACT(YEAR FROM P.CreationDate) * 12 + EXTRACT(MONTH FROM P.CreationDate))) AS MonthsSinceCreation,
      RANK() OVER (ORDER BY T.Count DESC) AS TagRank,
      P.CreationDate AS PostCreationDate
    FROM
      Tags T
      LEFT JOIN Posts P ON P.Tags IS NOT NULL
        AND POSITION('<' || T.TagName || '>' IN P.Tags) > 0
    WHERE
      P.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '6' MONTH)
  )
SELECT
  H.PostId,
  H.PostTypeId,
  H.CreationDate,
  H.Score,
  H.ViewCount,
  H.AnswerCount,
  H.Title,
  H.OwnerUserId,
  H.OwnerDisplayName,
  H.LastPostScore,
  H.PostRank,
  COALESCE(RC.CommentId, -1) AS RecentCommentId,
  COALESCE(RC.CommentScore, 0) AS RecentCommentScore,
  COALESCE(RC.CommentCreationDate, CAST('2024-10-01' AS date)) AS RecentCommentCreationDate,
  COALESCE(RC.CommentUserDisplayName, 'Anonymous') AS RecentCommentUserDisplayName,
  COALESCE(RC.CommentRank, 999999) AS RecentCommentRank,
  T.TagId,
  T.TagName,
  T.Count,
  T.ExcerptPostId,
  T.WikiPostId,
  T.MonthsSinceCreation,
  T.TagRank
FROM
  HighActivityPosts H
  LEFT JOIN RecentComments RC ON H.PostId = RC.PostId AND RC.CommentRank = 1
  LEFT JOIN TopTags T ON T.TagRank <= 10
      AND T.MonthsSinceCreation < 6
WHERE
  H.PostRank <= 5
  AND COALESCE(RC.CommentId, -1) != -1
ORDER BY
  H.PostId,
  T.TagRank,
  H.PostRank;