-- {"query": "4710.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1132} 

WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgPostScore,
      MAX(p.CreationDate) AS LatestPostDate
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalComments,
      AVG(c.Score) AS AvgCommentScore
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownVotes,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS TotalFavorites
    FROM Votes AS v
    JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  HighReputationUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      CASE WHEN u.WebsiteUrl IS NULL THEN 'No Website' WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'SO Related' ELSE 'External' END AS WebsiteCategory,
      DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users AS u
    WHERE
      u.Reputation >= 10000
  )
SELECT
  hru.DisplayName AS UserName,
  hru.Reputation,
  hru.ReputationRank,
  hru.WebsiteCategory,
  COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
  COALESCE(ups.QuestionCount, 0) AS UserQuestionCount,
  COALESCE(ups.AnswerCount, 0) AS UserAnswerCount,
  COALESCE(ups.AvgPostScore, 0) AS UserAvgPostScore,
  COALESCE(ucs.TotalComments, 0) AS UserTotalComments,
  COALESCE(ucs.AvgCommentScore, 0) AS UserAvgCommentScore,
  COALESCE(uvs.TotalUpVotes, 0) AS UserTotalUpVotes,
  COALESCE(uvs.TotalDownVotes, 0) AS UserTotalDownVotes,
  COALESCE(uvs.TotalFavorites, 0) AS UserTotalFavorites,
  COALESCE(ups.LatestPostDate, hru.CreationDate) AS LastActivityIndicator,
  COUNT(DISTINCT ph.PostId) AS PostsWithHistoryEdits,
  AVG(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS AvgHasEdits
FROM HighReputationUsers AS hru
LEFT JOIN UserPostStats AS ups
  ON hru.Id = ups.OwnerUserId
LEFT JOIN UserCommentStats AS ucs
  ON hru.Id = ucs.UserId
LEFT JOIN UserVoteStats AS uvs
  ON hru.Id = uvs.UserId
LEFT JOIN PostHistory AS ph
  ON hru.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) /* Edits and Rollbacks */
WHERE
  hru.ReputationRank <= 100 /* Top 100 by reputation */
GROUP BY
  hru.DisplayName,
  hru.Reputation,
  hru.ReputationRank,
  hru.WebsiteCategory,
  ups.TotalPosts,
  ups.QuestionCount,
  ups.AnswerCount,
  ups.AvgPostScore,
  ucs.TotalComments,
  ucs.AvgCommentScore,
  uvs.TotalUpVotes,
  uvs.TotalDownVotes,
  uvs.TotalFavorites,
  ups.LatestPostDate,
  hru.CreationDate
HAVING
  COUNT(DISTINCT ph.PostId) > 5 OR COUNT(DISTINCT ph.PostId) = 0
ORDER BY
  hru.Reputation DESC,
  UserTotalPosts DESC;
