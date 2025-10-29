-- {"query": "4210.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1372} 

WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      COUNT(a.Id) AS AnswerCountFromAnswersTable,
      MAX(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS HasAnswers,
      SUM(CASE WHEN c.CreationDate > p.CreationDate THEN 1 ELSE 0 END) AS CommentsOnQuestion,
      DENSE_RANK() OVER (ORDER BY p.Score DESC) AS RankByScore,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS QuestionNumberForOwner
    FROM
      Posts AS p
      JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN Users AS u
        ON p.OwnerUserId = u.Id
      LEFT JOIN Posts AS a
        ON p.Id = a.ParentId AND a.PostTypeId = 2
      LEFT JOIN Comments AS c
        ON p.Id = c.PostId
    WHERE
      p.PostTypeId = 1 AND p.DeletionDate IS NULL
    GROUP BY
      p.Id,
      p.Title,
      p.OwnerUserId,
      u.DisplayName,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate
  ),
  AnswerDetails AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      a.CreationDate AS AnswerCreationDate,
      a.Score AS AnswerScore,
      a.CommunityOwnedDate,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankByScoreForQuestion,
      CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAcceptedAnswer,
      COALESCE(a.OwnerUserId, -1) AS CoalescedOwnerUserId
    FROM
      Posts AS a
      JOIN PostTypes AS pt
        ON a.PostTypeId = pt.Id
      LEFT JOIN Users AS u
        ON a.OwnerUserId = u.Id
      LEFT JOIN QuestionDetails AS q
        ON a.ParentId = q.QuestionId
    WHERE
      a.PostTypeId = 2 AND a.DeletionDate IS NULL
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
      COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
      COUNT(CASE WHEN VoteTypeId = 5 THEN 1 END) AS FavoritesGiven,
      COUNT(DISTINCT PostId) AS DistinctPostsVotedOn,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVotes,
      MAX(CreationDate) AS LastVoteDate
    FROM
      Votes
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      CreationDate
    FROM
      Posts
    WHERE
      PostTypeId = 1
      AND CreationDate >= DATE('now', '-7 day')
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.OwnerDisplayName AS QuestionOwner,
  qd.QuestionCreationDate,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.FavoriteCount,
  qd.ClosedDate,
  qd.CommunityOwnedDate,
  qd.RankByScore,
  qd.QuestionNumberForOwner,
  ad.AnswerId,
  ad.OwnerDisplayName AS AnswerOwner,
  ad.AnswerCreationDate,
  ad.AnswerScore,
  ad.RankByScoreForQuestion,
  ad.IsAcceptedAnswer,
  COALESCE(ua.UpVotesGiven, 0) AS UserUpVotesGiven,
  COALESCE(ua.DownVotesGiven, 0) AS UserDownVotesGiven,
  COALESCE(ua.NetVotes, 0) AS UserNetVotes,
  CASE
    WHEN qd.OwnerUserId = ad.CoalescedOwnerUserId THEN 'Self-Answered'
    ELSE 'Not Self-Answered'
  END AS SelfAnswerStatus,
  CASE
    WHEN rq.Id IS NOT NULL THEN 'Recent'
    ELSE 'Not Recent'
  END AS IsRecentQuestion,
  CHAR_LENGTH(qd.QuestionTitle) AS TitleLength,
  (
    SELECT
      SUM(Score)
    FROM
      Posts
    WHERE
      ParentId = qd.QuestionId AND PostTypeId = 2
  ) AS TotalAnswerScore
FROM
  QuestionDetails AS qd
FULL OUTER JOIN
  AnswerDetails AS ad
  ON qd.QuestionId = ad.QuestionId
LEFT JOIN
  UserActivity AS ua
  ON qd.OwnerUserId = ua.UserId
LEFT JOIN
  RecentQuestions AS rq
  ON qd.QuestionId = rq.Id AND qd.OwnerUserId = rq.OwnerUserId
WHERE
  qd.QuestionScore > 10
  AND qd.AnswerCountFromAnswersTable > 0
  AND ad.AnswerScore > 5
  OR qd.QuestionId IS NULL AND ad.AnswerId IS NOT NULL
ORDER BY
  qd.QuestionCreationDate DESC,
  ad.AnswerScore DESC
LIMIT 100;
