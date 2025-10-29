-- {"query": "4086.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1180} 

WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalComments,
      AVG(c.Score) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
      MAX(v.CreationDate) AS LastVoteDate
    FROM Votes AS v
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  HighlyActiveUsers AS (
    SELECT
      u.Id
    FROM Users AS u
    JOIN UserPostStats AS ups
      ON u.Id = ups.OwnerUserId
    JOIN UserCommentStats AS ucs
      ON u.Id = ucs.UserId
    WHERE
      ups.TotalPosts > 1000
      AND ucs.TotalComments > 5000
      AND u.Reputation > 50000
      AND u.Views > 100000
  ),
  TopQuestions AS (
    SELECT
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.AnswerCount DESC) AS RowNum
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1
      AND p.Score > 100
      AND p.AnswerCount > 10
  )
SELECT
  ha.Id AS UserId,
  u.DisplayName,
  ups.TotalPosts,
  ucs.TotalComments,
  uvs.UpVotesGiven,
  uvs.DownVotesGiven,
  tq.Title AS TopQuestionTitle,
  tq.Score AS TopQuestionScore,
  CASE
    WHEN DATEDIFF(day, u.CreationDate, GETDATE()) > 365
    THEN 'Veteran'
    WHEN DATEDIFF(day, u.CreationDate, GETDATE()) > 90
    THEN 'Experienced'
    ELSE 'Newbie'
  END AS UserStatus,
  COALESCE(u.Location, 'Unknown') AS UserLocation,
  CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
  (
    SELECT
      MAX(ph.CreationDate)
    FROM PostHistory AS ph
    WHERE
      ph.UserId = u.Id
      AND ph.PostHistoryTypeId IN (4, 5, 6) /* Edits */
  ) AS LastEditDateForUser,
  CONCAT(
    'User ',
    u.DisplayName,
    ' has created ',
    ups.TotalPosts,
    ' posts and received ',
    COALESCE(CAST(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS VARCHAR), '0'),
    ' upvotes on their posts. Their latest activity was on ',
    FORMAT(u.LastAccessDate, 'yyyy-MM-dd HH:mm:ss')
  ) AS UserSummary,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Name LIKE '%Gold%' AND b.Class = 1
    )
    THEN 'Has Gold Badge'
    ELSE 'No Gold Badge'
  END AS HasGoldBadge
FROM HighlyActiveUsers AS ha
JOIN Users AS u
  ON ha.Id = u.Id
LEFT JOIN UserPostStats AS ups
  ON u.Id = ups.OwnerUserId
LEFT JOIN UserCommentStats AS ucs
  ON u.Id = ucs.UserId
LEFT JOIN UserVoteStats AS uvs
  ON u.Id = uvs.UserId
LEFT JOIN TopQuestions AS tq
  ON ha.Id = tq.OwnerUserId AND tq.RowNum = 1
WHERE
  u.DisplayName IS NOT NULL
  AND u.Reputation BETWEEN 10000 AND 100000
  AND u.DownVotes < u.UpVotes * 0.1
ORDER BY
  u.Reputation DESC;
