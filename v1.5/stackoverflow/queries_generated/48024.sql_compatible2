WITH
  HighScoringPosts AS (
    SELECT
      p.Id,
      p.Title,
      p.Score,
      p.AnswerCount,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.Score > 1000
      AND p.AnswerCount > 10
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
  ),
  RecentActivity AS (
    SELECT
      ph.PostId,
      COUNT(ph.Id) AS ActivityCount,
      MAX(ph.CreationDate) AS LastActivityDate
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (2, 4, 5, 6)
    GROUP BY
      ph.PostId
    HAVING
      COUNT(ph.Id) > 5
  ),
  PostEngagement AS (
    SELECT
      p.Id,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount,
      AVG(CAST(c.Score AS REAL)) AS AvgCommentScore
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id
  )
SELECT
  hsp.Id,
  hsp.Title,
  hsp.Score AS PostScore,
  hsp.AnswerCount AS PostAnswerCount,
  hsp.OwnerDisplayName,
  hsp.CreationDate AS PostCreationDate,
  ra.ActivityCount AS HistoryActivityCount,
  ra.LastActivityDate AS LastHistoryActivity,
  pe.CommentCount AS TotalComments,
  pe.VoteCount AS TotalVotes,
  pe.AvgCommentScore
FROM HighScoringPosts AS hsp
LEFT JOIN RecentActivity AS ra
  ON hsp.Id = ra.PostId
JOIN PostEngagement AS pe
  ON hsp.Id = pe.Id
ORDER BY
  hsp.Score DESC,
  hsp.AnswerCount DESC,
  ra.ActivityCount DESC,
  pe.VoteCount DESC
LIMIT 100;