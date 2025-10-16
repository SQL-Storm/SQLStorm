-- {"query": "18029.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1355} 

WITH
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount,
      MAX(p.LastActivityDate) AS LastActivity
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    LEFT JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      u.CreationDate >= '2020-01-01'
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      COUNT(DISTINCT c.Id) AS CommentCountPerPost,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.CreationDate >= '2021-01-01' AND p.PostTypeId IN (1, 2)
    GROUP BY
      p.Id,
      p.Title,
      p.PostTypeId,
      pt.Name,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount
  ),
  UserPostScore AS (
    SELECT
      ua.UserId,
      ua.DisplayName,
      ua.Reputation,
      pe.PostId,
      pe.Title,
      pe.Score,
      pe.CommentCountPerPost,
      pe.UpVotes,
      pe.DownVotes,
      pe.ScoreRank,
      pe.PreviousScore,
      CASE
        WHEN pe.Score > 0 THEN 'Positive'
        WHEN pe.Score < 0 THEN 'Negative'
        ELSE 'Neutral'
      END AS ScoreCategory,
      CONCAT(
        ua.DisplayName,
        ' (',
        ua.Reputation,
        ')'
      ) AS UserIdentifier
    FROM UserActivity AS ua
    JOIN PostEngagement AS pe
      ON ua.UserId = pe.OwnerUserId
    WHERE
      pe.ScoreRank <= 5
  )
SELECT
  ups.UserId,
  ups.UserIdentifier,
  ups.Reputation,
  ups.PostId,
  ups.Title,
  ups.Score,
  ups.CommentCountPerPost,
  ups.UpVotes,
  ups.DownVotes,
  ups.ScoreRank,
  ups.PreviousScore,
  ups.ScoreCategory,
  COALESCE(
    (
      SELECT
        MAX(ph.CreationDate)
      FROM PostHistory AS ph
      WHERE
        ph.PostId = ups.PostId AND ph.PostHistoryTypeId IN (4, 5) /* Edit Title or Edit Body */
    ),
    ups.CreationDate
  ) AS LastEditOrCreation,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = ups.PostId OR pl.RelatedPostId = ups.PostId
  ) AS RelatedPostsCount
FROM UserPostScore AS ups
WHERE
  ups.Score > 100
UNION ALL
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  NULL,
  'Summary Row',
  NULL,
  SUM(ua.CommentCount),
  SUM(
    CASE
      WHEN v.VoteTypeId = 2 THEN 1
      ELSE 0
    END
  ),
  SUM(
    CASE
      WHEN v.VoteTypeId = 3 THEN 1
      ELSE 0
    END
  ),
  NULL,
  NULL,
  NULL,
  MAX(ua.LastActivity),
  COUNT(DISTINCT pl.Id)
FROM UserActivity AS ua
LEFT JOIN Votes AS v
  ON ua.UserId = v.UserId
LEFT JOIN Posts AS p
  ON ua.UserId = p.OwnerUserId
LEFT JOIN PostLinks AS pl
  ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
WHERE
  ua.TotalPosts > 1000
GROUP BY
  ua.UserId,
  ua.DisplayName,
  ua.Reputation
ORDER BY
  Reputation DESC,
  TotalPosts DESC;
