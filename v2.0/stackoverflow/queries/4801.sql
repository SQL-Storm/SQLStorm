-- {"query": "4801.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1211} 
WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RowNum,
      LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousDayScore,
      LEAD(p.ViewCount, 1, 0) OVER (ORDER BY p.CreationDate) AS NextDayViewCount,
      SUM(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS Rolling10DayScore,
      AVG(CAST(p.AnswerCount AS DECIMAL)) OVER (ORDER BY p.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS Rolling30DayAvgAnswerCount,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM
      Posts AS p
      JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
      LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2) AND p.CreationDate >= '2023-01-01'
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS NumberOfComments,
      MAX(CreationDate) AS LastCommentDate
    FROM
      Comments
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  HighEngagementUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COALESCE(ua.NumberOfComments, 0) AS TotalComments,
      COALESCE(ua.LastCommentDate, u.CreationDate) AS LastActivityDate,
      CASE
        WHEN u.Views > 10000 THEN 'High Viewer'
        WHEN u.UpVotes > 5000 THEN 'High Upvoter'
        ELSE 'Standard'
      END AS UserEngagementLevel
    FROM
      Users AS u
      LEFT JOIN UserActivity AS ua
      ON u.Id = ua.UserId
    WHERE
      u.Reputation > 1000 AND u.CreationDate < '2023-07-01'
  )
SELECT
  rp.PostId,
  rp.PostTypeName,
  rp.OwnerDisplayName,
  rp.PostCreationDate,
  rp.Score,
  rp.ViewCount,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.IsClosed,
  rp.PreviousDayScore,
  rp.NextDayViewCount,
  rp.Rolling10DayScore,
  rp.Rolling30DayAvgAnswerCount,
  he.DisplayName AS EngagingUserDisplayName,
  he.Reputation AS EngagingUserReputation,
  he.UserEngagementLevel,
  CASE
    WHEN rp.Score > 100 AND rp.AnswerCount > 10 THEN 'Popular'
    WHEN rp.Score < 0 AND rp.ClosedDate IS NOT NULL THEN 'Controversial Closed'
    ELSE 'Standard'
  END AS PostStatusCategory,
  UPPER(LEFT(COALESCE(rp.OwnerDisplayName, 'Anonymous'), 3)) AS OwnerDisplayNamePrefix,
  COALESCE(rp.ClosedDate, rp.PostCreationDate) AS EffectiveDate,
  (
    SELECT
      COUNT(*)
    FROM
      PostHistory AS ph
    WHERE
      ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (4, 5) -- Edits
  ) AS NumberOfEdits,
  (
    SELECT
      COUNT(*)
    FROM
      Comments AS c
    WHERE
      c.PostId = rp.PostId
  ) AS TotalCommentsOnPost,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks AS pl
      WHERE
        pl.PostId = rp.PostId AND pl.LinkTypeId = 3 -- Duplicate link
    ) THEN 'Linked as Duplicate'
    ELSE 'Not Linked as Duplicate'
  END AS DuplicateLinkStatus
FROM
  RankedPosts AS rp
  LEFT JOIN HighEngagementUsers AS he
  ON rp.OwnerUserId = he.UserId
WHERE
  rp.RowNum <= 100
  AND rp.Score > HE.Reputation / 100.0 -- Score is at least 1% of the owner's reputation
  AND (rp.ViewCount > 1000 OR rp.AnswerCount > 5)
  AND rp.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
ORDER BY
  rp.PostCreationDate DESC,
  rp.Score DESC
LIMIT 500;