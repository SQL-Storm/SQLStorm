WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.CreationDate,
      ph.Text,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
  ),
  LatestQuestionHistory AS (
    SELECT
      ph.PostId,
      ph.UserId AS LatestEditorUserId,
      ph.CreationDate AS LatestEditDate,
      ph.Text AS LatestBodyContent,
      ph.PostHistoryTypeId,
      pt.Name AS PostHistoryTypeName
    FROM RankedPostHistory ph
    JOIN PostHistoryTypes pt
      ON ph.PostHistoryTypeId = pt.Id
    WHERE
      ph.rn = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v
      ON u.Id = v.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.CreationDate AS QuestionCreationDate,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      q.AnswerCount AS QuestionAnswerCount,
      q.FavoriteCount AS QuestionFavoriteCount,
      q.ClosedDate AS QuestionClosedDate,
      q.Tags,
      lq.LatestEditDate,
      lq.LatestBodyContent,
      lq.PostHistoryTypeName,
      COALESCE(u.DisplayName, q.OwnerDisplayName) AS OwnerDisplayName,
      COALESCE(ua.Reputation, u.Reputation) AS OwnerReputation,
      COALESCE(ua.QuestionCount, 0) AS OwnerTotalQuestions,
      COALESCE(ua.AnswerCount, 0) AS OwnerTotalAnswers,
      COALESCE(ua.UpVoteCount, 0) AS OwnerTotalUpVotes,
      COALESCE(ua.DownVoteCount, 0) AS OwnerTotalDownVotes
    FROM Posts q
    LEFT JOIN LatestQuestionHistory lq
      ON q.Id = lq.PostId
    LEFT JOIN Users u
      ON q.OwnerUserId = u.Id
    LEFT JOIN UserActivity ua
      ON u.Id = ua.UserId
    WHERE
      q.PostTypeId = 1
  )
SELECT
  qd.QuestionId,
  qd.Title AS QuestionTitle,
  qd.QuestionCreationDate,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  qd.OwnerTotalQuestions,
  qd.OwnerTotalAnswers,
  qd.OwnerTotalUpVotes,
  qd.OwnerTotalDownVotes,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionAnswerCount,
  qd.QuestionFavoriteCount,
  qd.QuestionClosedDate,
  qd.Tags,
  qd.LatestEditDate,
  qd.LatestBodyContent,
  qd.PostHistoryTypeName,
  CASE
    WHEN qd.QuestionClosedDate IS NOT NULL THEN 'Closed'
    WHEN qd.QuestionScore > 100 THEN 'High Score'
    WHEN qd.QuestionViewCount > 10000 THEN 'High View Count'
    ELSE 'Standard'
  END AS QuestionCategory,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.PostId = qd.QuestionId AND c.Score > 5
  ) AS HighScoreCommentCount,
  (
    SELECT
      COUNT(DISTINCT l.RelatedPostId)
    FROM PostLinks l
    WHERE
      l.PostId = qd.QuestionId AND l.LinkTypeId = 3
  ) AS DuplicateLinkCount,
  STRING_AGG(DISTINCT b.Name, ', ') AS UserBadges,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM Posts a
      WHERE a.ParentId = qd.QuestionId AND a.Score > 10
    ) THEN 'Has Highly Scored Answer'
    ELSE 'No Highly Scored Answer'
  END AS AnswerStatus
FROM QuestionDetails qd
LEFT JOIN Badges b
  ON qd.QuestionOwnerUserId = b.UserId AND b.Class IN (1, 2)
GROUP BY
  qd.QuestionId,
  qd.Title,
  qd.QuestionCreationDate,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  qd.OwnerTotalQuestions,
  qd.OwnerTotalAnswers,
  qd.OwnerTotalUpVotes,
  qd.OwnerTotalDownVotes,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionAnswerCount,
  qd.QuestionFavoriteCount,
  qd.QuestionClosedDate,
  qd.Tags,
  qd.LatestEditDate,
  qd.LatestBodyContent,
  qd.PostHistoryTypeName,
  qd.QuestionOwnerUserId
HAVING
  qd.QuestionScore > 0 OR qd.QuestionAnswerCount > 0 OR qd.QuestionFavoriteCount > 0
ORDER BY
  qd.QuestionScore DESC,
  qd.QuestionViewCount DESC
LIMIT 100;