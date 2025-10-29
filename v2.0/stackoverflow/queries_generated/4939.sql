-- {"query": "4939.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1343} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate AS PostCreationDate,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
      SUM(v.VoteTypeId) OVER (PARTITION BY p.Id) AS TotalVotes
    FROM
      Posts AS p
      LEFT JOIN Users AS u
        ON p.OwnerUserId = u.Id
      LEFT JOIN Comments AS c
        ON p.Id = c.PostId
      LEFT JOIN Votes AS v
        ON p.Id = v.PostId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.Score > 0
      AND p.ViewCount > 100
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      u.DisplayName,
      u.Reputation
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS PostsOwned,
      COUNT(DISTINCT CASE WHEN c.UserId = u.Id THEN c.Id ELSE NULL END) AS CommentsMade,
      COUNT(DISTINCT CASE WHEN v.UserId = u.Id THEN v.Id ELSE NULL END) AS VotesCast,
      AVG(p.Score) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM
      Users AS u
      LEFT JOIN Posts AS p
        ON u.Id = p.OwnerUserId
      LEFT JOIN Comments AS c
        ON u.Id = c.UserId
      LEFT JOIN Votes AS v
        ON u.Id = v.UserId
    WHERE
      u.Reputation > 1000
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  PostHistoryAnalysis AS (
    SELECT
      ph.PostId,
      COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.Id ELSE NULL END) AS TitleEdits,
      COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.Id ELSE NULL END) AS BodyEdits,
      COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 6 THEN ph.Id ELSE NULL END) AS TagEdits,
      MAX(ph.CreationDate) AS LastHistoryDate
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      ph.PostId
  )
SELECT
  rp.PostId,
  rp.PostTypeId,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.Reputation,
  rp.Score,
  rp.ViewCount,
  rp.AnswerCount,
  rp.CommentCountForPost,
  rp.FavoriteCount,
  rp.PostRank,
  rp.TotalVotes,
  COALESCE(ua.PostsOwned, 0) AS UserPostsOwned,
  COALESCE(ua.CommentsMade, 0) AS UserCommentsMade,
  COALESCE(ua.VotesCast, 0) AS UserVotesCast,
  COALESCE(ua.AvgPostScore, 0) AS UserAvgPostScore,
  COALESCE(pha.TitleEdits, 0) AS PostTitleEdits,
  COALESCE(pha.BodyEdits, 0) AS PostBodyEdits,
  COALESCE(pha.TagEdits, 0) AS PostTagEdits,
  CASE
    WHEN rp.PostCreationDate < DATE('now', '-1 year') THEN 'Old'
    WHEN rp.PostCreationDate >= DATE('now', '-1 year') THEN 'New'
    ELSE 'Unknown'
  END AS PostAgeCategory,
  CASE
    WHEN rp.Score > rp.ViewCount * 0.05 THEN 'High Engagement'
    WHEN rp.Score > rp.ViewCount * 0.01 THEN 'Medium Engagement'
    ELSE 'Low Engagement'
  END AS EngagementRatio,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks AS pl
      WHERE
        pl.PostId = rp.PostId
        AND pl.LinkTypeId = 3
    ) THEN 'IsDuplicate'
    ELSE 'NotDuplicate'
  END AS DuplicateStatus,
  CONCAT(
    'Owner: ',
    rp.OwnerDisplayName,
    ' | Score: ',
    rp.Score,
    ' | Views: ',
    rp.ViewCount
  ) AS PostSummary,
  rp.PostCreationDate,
  COALESCE(ua.LastPostDate, rp.PostCreationDate) AS LastActivityTimestamp
FROM
  RankedPosts AS rp
FULL OUTER JOIN
  UserActivity AS ua
  ON rp.OwnerUserId = ua.UserId
LEFT JOIN
  PostHistoryAnalysis AS pha
  ON rp.PostId = pha.PostId
WHERE
  rp.PostRank <= 1000
  AND (
    rp.OwnerUserId IS NULL
    OR rp.Reputation > 5000
  )
ORDER BY
  rp.PostRank,
  rp.Score DESC;
