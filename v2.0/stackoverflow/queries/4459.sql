-- {"query": "4459.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1176} 
WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.CommentCount,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ASC) AS rn_asc,
      AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS previous_score
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserDisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEditCount,
      MAX(ph.CreationDate) AS LastPostHistoryDate
    FROM Users AS u
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
    HAVING
      u.Reputation > 1000
  ),
  PostInteraction AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT c.Id) AS CommentCountOnPost,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      COUNT(DISTINCT pl.Id) AS PostLinkCount
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN PostLinks AS pl
      ON p.Id = pl.PostId
    WHERE
      p.PostTypeId = 1 -- Questions only
    GROUP BY
      p.Id
  )
SELECT
  rp.PostId,
  rp.Title,
  rp.PostTypeName,
  rp.PostScore,
  rp.PostViewCount,
  rp.AnswerCount,
  rp.CommentCount AS PostCommentCount,
  ua.UserDisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.PostHistoryCount,
  ua.BodyEditCount,
  ua.LastPostHistoryDate,
  pi.CommentCountOnPost,
  pi.UpVoteCount,
  pi.DownVoteCount,
  pi.PostLinkCount,
  rp.avg_score_by_type,
  rp.previous_score,
  CASE
    WHEN rp.PostScore > rp.avg_score_by_type THEN 'Above Average'
    WHEN rp.PostScore < rp.avg_score_by_type THEN 'Below Average'
    ELSE 'Average'
  END AS ScoreCategory,
  CASE
    WHEN ua.LastPostHistoryDate IS NOT NULL AND ua.LastPostHistoryDate > ua.UserCreationDate + INTERVAL '30 days' THEN 'Active User'
    ELSE 'Inactive User'
  END AS UserActivityStatus,
  CASE
    WHEN rp.AnswerCount > 0 AND rp.CommentCount > rp.AnswerCount * 2 THEN 'High Comment Ratio'
    WHEN rp.AnswerCount = 0 AND rp.CommentCount > 5 THEN 'No Answers, Many Comments'
    ELSE 'Standard Interaction'
  END AS PostInteractionPattern,
  COALESCE(ua.UserDisplayName, 'Community') AS DisplayNameOrCommunity,
  rp.rn_desc,
  rp.rn_asc,
  rp.PostCreationDate
FROM RankedPosts AS rp
LEFT JOIN UserActivity AS ua
  ON rp.OwnerUserId = ua.UserId
LEFT JOIN PostInteraction AS pi
  ON rp.PostId = pi.PostId
WHERE
  rp.rn_desc <= 100 -- Top 100 newest posts of each type
  AND rp.PostScore > 0
  AND rp.PostViewCount > (rp.PostScore * 10)
  AND pi.UpVoteCount > pi.DownVoteCount * 5
  AND ua.PostHistoryCount > 10
ORDER BY
  rp.PostCreationDate DESC
LIMIT 500;