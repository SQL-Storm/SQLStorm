-- {"query": "4365.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1162} 
WITH RankedPostEdits AS (
  SELECT
    ph.PostId,
    ph.UserId,
    ph.CreationDate,
    p.OwnerUserId,
    p.Id AS PostId_Post,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
  FROM PostHistory ph
  JOIN Posts p
    ON ph.PostId = p.Id
  WHERE
    ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL AND p.OwnerUserId IS NOT NULL
),
UserEditContribution AS (
  SELECT
    rpe.UserId,
    COUNT(DISTINCT rpe.PostId) AS DistinctPostsEdited,
    SUM(CASE WHEN rpe.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS OwnPostsEdited,
    AVG(julianday('now') - julianday(p.CreationDate)) AS AvgPostAgeAtEdit,
    MAX(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS EverClosedPost
  FROM RankedPostEdits rpe
  JOIN Posts p
    ON rpe.PostId = p.Id
  GROUP BY
    rpe.UserId
  HAVING
    COUNT(DISTINCT rpe.PostId) > 5
),
TagPopularity AS (
  SELECT
    SUBSTRING(t.TagName, 1, 3) AS TagPrefix,
    AVG(p.AnswerCount) AS AvgAnswersForTag,
    COUNT(DISTINCT p.Id) AS PostsWithTag
  FROM Tags t
  JOIN Posts p
    ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
  GROUP BY
    TagPrefix
  HAVING
    COUNT(DISTINCT p.Id) > 1000
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount,
    SUM(CASE WHEN p.OwnerUserId = u.Id THEN p.Score ELSE 0 END) AS ScoreOnOwnPosts,
    (
      SELECT
        COUNT(*)
      FROM Badges b
      WHERE
        b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount
  FROM Users u
  LEFT JOIN Comments c
    ON u.Id = c.UserId
  LEFT JOIN Votes v
    ON u.Id = v.UserId
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  GROUP BY
    u.Id
  HAVING
    COUNT(DISTINCT c.Id) > 10 OR COUNT(DISTINCT v.Id) > 50
)
SELECT
  ue.UserId,
  ue.CommentCount,
  ue.UpVoteCount,
  ue.DownVoteCount,
  ue.ScoreOnOwnPosts,
  ue.GoldBadgeCount,
  COALESCE(tp.AvgAnswersForTag, 0) AS AvgAnswersOnRelatedTags,
  CASE WHEN uec.EverClosedPost = 1 THEN 'Yes' ELSE 'No' END AS EditedClosedPost,
  CONCAT(u.DisplayName, ' (', u.Reputation, ')') AS UserIdentifier,
  CASE WHEN u.EmailHash IS NULL THEN 'No Email' WHEN u.EmailHash = '' THEN 'No Email' ELSE 'Has Email' END AS EmailStatus,
  CASE WHEN uec.DistinctPostsEdited IS NULL THEN 0 ELSE uec.DistinctPostsEdited END AS TotalEdits,
  CASE WHEN uec.OwnPostsEdited IS NULL THEN 0 ELSE uec.OwnPostsEdited END AS OwnEdits,
  CASE WHEN uec.AvgPostAgeAtEdit IS NULL THEN 0 ELSE ROUND(uec.AvgPostAgeAtEdit, 2) END AS AvgAgeOfEditedPosts
FROM UserEngagement ue
LEFT JOIN Users u
  ON ue.UserId = u.Id
LEFT JOIN UserEditContribution uec
  ON ue.UserId = uec.UserId
LEFT JOIN Tags t
  ON u.DisplayName LIKE '%' || t.TagName || '%'
LEFT JOIN TagPopularity tp
  ON SUBSTRING(t.TagName, 1, 3) = tp.TagPrefix
WHERE
  u.Views > 1000 AND u.UpVotes > 500
GROUP BY
  ue.UserId,
  ue.CommentCount,
  ue.UpVoteCount,
  ue.DownVoteCount,
  ue.ScoreOnOwnPosts,
  ue.GoldBadgeCount,
  tp.AvgAnswersForTag,
  uec.EverClosedPost,
  UserIdentifier,
  EmailStatus,
  TotalEdits,
  OwnEdits,
  AvgAgeOfEditedPosts
HAVING
  COUNT(DISTINCT t.TagName) < 5 OR MAX(tp.PostsWithTag) > 5000;