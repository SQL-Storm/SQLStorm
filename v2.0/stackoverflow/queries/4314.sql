-- {"query": "4314.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1562}
WITH
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS PostCount
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  UserCommentCounts AS (
    SELECT
      UserId,
      COUNT(Id) AS CommentCount
    FROM
      Comments
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  UserVoteCounts AS (
    SELECT
      UserId,
      COUNT(Id) AS VoteCount
    FROM
      Votes
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  UserReputation AS (
    SELECT
      Id,
      Reputation,
      DisplayName,
      CreationDate
    FROM
      Users
  ),
  MostProlificUsers AS (
    SELECT
      ur.Id,
      ur.DisplayName,
      ur.Reputation,
      ur.CreationDate,
      COALESCE(upc.PostCount, 0) AS TotalPosts,
      COALESCE(ucc.CommentCount, 0) AS TotalComments,
      COALESCE(uvc.VoteCount, 0) AS TotalVotes,
      (
        COALESCE(upc.PostCount, 0) + COALESCE(ucc.CommentCount, 0) + COALESCE(uvc.VoteCount, 0)
      ) AS TotalActivity
    FROM
      UserReputation ur
      LEFT JOIN UserPostCounts upc ON ur.Id = upc.OwnerUserId
      LEFT JOIN UserCommentCounts ucc ON ur.Id = ucc.UserId
      LEFT JOIN UserVoteCounts uvc ON ur.Id = uvc.UserId
    WHERE
      ur.CreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
      AND ur.Reputation > 1000
    ORDER BY
      TotalActivity DESC
    LIMIT 100
  ),
  PostDetails AS (
    SELECT
      p.Id AS PostId,
      pt.Name AS PostType,
      p.Title,
      p.Score,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus,
      SUBSTRING(Tags FROM 2 FOR (CHAR_LENGTH(Tags) - 2)) AS CleanTags,
      CASE
        WHEN p.OwnerUserId = -1 THEN 'Community'
        ELSE (
          SELECT
            DisplayName
          FROM
            Users
          WHERE
            Id = p.OwnerUserId
          LIMIT 1
        )
      END AS OwnerDisplayNameCorrelated
    FROM
      Posts p
      JOIN PostTypes pt ON p.PostTypeId = pt.Id
      LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2)
  ),
  HighScoringPosts AS (
    SELECT
      pd.PostId,
      pd.PostType,
      pd.Title,
      pd.Score,
      pd.CommentCount,
      pd.FavoriteCount,
      pd.CreationDate,
      pd.OwnerUserId,
      pd.OwnerDisplayName,
      pd.PostStatus,
      pd.CleanTags,
      ROW_NUMBER() OVER (
        PARTITION BY
          pd.PostType
        ORDER BY
          pd.Score DESC,
          pd.FavoriteCount DESC
      ) AS RankByType
    FROM
      PostDetails pd
    WHERE
      pd.Score > 50
      AND pd.FavoriteCount > 10
  ),
  TagInfluence AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT ph.PostId) AS PostsWithTag,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AvgPostScoreForTag,
      SUM(CAST(p.FavoriteCount AS BIGINT)) AS TotalFavoritesForTag,
      MAX(p.CreationDate) AS LatestPostDateForTag
    FROM
      Tags t
      JOIN Posts p ON POSITION(t.TagName IN p.Tags) > 0
      JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE
      t.TagName IS NOT NULL
      AND t.TagName NOT LIKE '#%' -- Exclude Meta tags
    GROUP BY
      t.TagName
    HAVING
      COUNT(DISTINCT ph.PostId) > 50
  ),
  UserContributionSummary AS (
    SELECT
      mpu.Id AS UserId,
      mpu.DisplayName,
      mpu.Reputation,
      mpu.TotalPosts,
      mpu.TotalComments,
      mpu.TotalVotes,
      mpu.TotalActivity,
      CASE
        WHEN mpu.TotalActivity > 10000 THEN 'Highly Active'
        WHEN mpu.TotalActivity > 1000 THEN 'Moderately Active'
        ELSE 'Less Active'
      END AS ActivityLevel,
      COUNT(DISTINCT hsp.PostId) AS HighScoringPostCount
    FROM
      MostProlificUsers mpu
      LEFT JOIN HighScoringPosts hsp ON mpu.Id = hsp.OwnerUserId
    GROUP BY
      mpu.Id,
      mpu.DisplayName,
      mpu.Reputation,
      mpu.TotalPosts,
      mpu.TotalComments,
      mpu.TotalVotes,
      mpu.TotalActivity
  )
SELECT
  'Benchmark Results' AS QueryCategory,
  ti.TagName,
  ti.AvgPostScoreForTag,
  ti.TotalFavoritesForTag,
  ti.LatestPostDateForTag,
  ucs.UserId,
  ucs.DisplayName,
  ucs.Reputation,
  ucs.ActivityLevel,
  ucs.HighScoringPostCount,
  CASE
    WHEN ucs.Reputation > 50000 THEN 'Expert'
    WHEN ucs.Reputation > 10000 THEN 'Advanced'
    WHEN ucs.Reputation > 1000 THEN 'Intermediate'
    ELSE 'Beginner'
  END AS ReputationLevel,
  COALESCE(CAST(ucs.HighScoringPostCount AS VARCHAR(10)), 'None') AS HighScoringPostsStr
FROM
  TagInfluence ti
FULL OUTER JOIN UserContributionSummary ucs ON ti.TagName = ucs.DisplayName
WHERE
  ti.TagName IS NOT NULL
  AND ucs.UserId IS NOT NULL
  AND (ti.TotalFavoritesForTag > 100000
       OR ucs.Reputation > 100000)
ORDER BY
  ti.TotalFavoritesForTag DESC,
  ucs.Reputation DESC;