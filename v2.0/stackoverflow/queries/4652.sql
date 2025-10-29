WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswererUserId,
      u.DisplayName AS AnswererDisplayName,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankNum,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS PreviousScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS NextScore,
      COUNT(p.Id) OVER (PARTITION BY p.ParentId) AS AnswerCountForQuestion
    FROM
      Posts p
    JOIN
      PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN
      Users u
      ON p.OwnerUserId = u.Id
    WHERE
      pt.Name = 'Answer' AND p.ParentId IS NOT NULL
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title AS QuestionTitle,
      q.Tags AS QuestionTags,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      q.AnswerCount AS QuestionAnswerCount,
      q.CommunityOwnedDate,
      CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id AND c.CreationDate > q.CreationDate) AS CommentCountAfterCreation,
      DENSE_RANK() OVER (ORDER BY q.Score DESC) AS GlobalQuestionScoreRank,
      q.OwnerUserId AS QuestionOwnerUserId
    FROM
      Posts q
    WHERE
      q.PostTypeId = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
      MAX(p.CreationDate) AS LastPostCreationDate,
      AVG(p.Score) AS AveragePostScore
    FROM
      Users u
    LEFT JOIN
      Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN
      PostTypes pt
      ON p.PostTypeId = pt.Id
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionTags,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionAnswerCount,
  qd.IsClosed,
  qd.GlobalQuestionScoreRank,
  ua.DisplayName AS QuestionOwnerDisplayName,
  ua.Reputation AS QuestionOwnerReputation,
  ua.TotalPostsOwned AS QuestionOwnerTotalPosts,
  ra.RankNum AS TopAnswerRank,
  ra.AnswererDisplayName,
  ra.AnswerScore AS TopAnswerScore,
  ra.AnswerCountForQuestion,
  CASE
    WHEN ra.RankNum = 1 THEN 'Best'
    WHEN ra.RankNum <= 3 THEN 'Top 3'
    ELSE 'Other'
  END AS TopAnswerCategory,
  COALESCE(ra.AnswerScore - ra.PreviousScore, 0) AS ScoreDifferenceWithPreviousAnswer,
  CASE
    WHEN qd.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    WHEN qd.QuestionScore > 1000 AND qd.QuestionAnswerCount > 10 THEN 'High Engagement'
    WHEN qd.IsClosed = 1 THEN 'Closed'
    ELSE 'Active'
  END AS QuestionStatusCategory,
  (
    SELECT
      COUNT(ph.Id)
    FROM
      PostHistory ph
    WHERE
      ph.PostId = qd.QuestionId
      AND ph.PostHistoryTypeId IN (4, 5, 6)
  ) AS EditHistoryCount,
  (
    SELECT
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
    FROM
      Votes v
    WHERE
      v.PostId = qd.QuestionId
  ) AS TotalUpvotes,
  (
    SELECT
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
    FROM
      Votes v
    WHERE
      v.PostId = qd.QuestionId
  ) AS TotalDownvotes,
  STRING_AGG(DISTINCT pht.Name, ', ') AS PostTypesInHistory
FROM
  QuestionDetails qd
LEFT JOIN
  UserActivity ua
  ON qd.QuestionOwnerUserId = ua.UserId
LEFT JOIN
  RankedAnswers ra
  ON qd.QuestionId = ra.QuestionId AND ra.RankNum = 1
LEFT JOIN
  PostHistory ph
  ON qd.QuestionId = ph.PostId
LEFT JOIN
  PostHistoryTypes pht
  ON ph.PostHistoryTypeId = pht.Id
GROUP BY
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionTags,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionAnswerCount,
  qd.IsClosed,
  qd.GlobalQuestionScoreRank,
  ua.DisplayName,
  ua.Reputation,
  ua.TotalPostsOwned,
  ra.RankNum,
  ra.AnswererDisplayName,
  ra.AnswerScore,
  ra.AnswerCountForQuestion,
  ra.PreviousScore,
  qd.CommunityOwnedDate,
  qd.QuestionOwnerUserId
HAVING
  qd.QuestionAnswerCount > 0 AND qd.QuestionScore > 0
ORDER BY
  qd.QuestionScore DESC,
  qd.QuestionViewCount DESC
LIMIT 100;