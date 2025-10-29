-- {"query": "4443.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1377} 
WITH RankedAnswers AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.OwnerUserId,
    a.Score,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
  FROM Posts AS a
  WHERE
    a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
),
QuestionDetails AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.OwnerUserId AS QuestionOwnerUserId,
    q.CreationDate AS QuestionCreationDate,
    q.Score AS QuestionScore,
    q.ViewCount AS QuestionViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.ClosedDate,
    q.Tags,
    (
      SELECT
        SUM(COALESCE(c.Score, 0))
      FROM Comments AS c
      WHERE
        c.PostId = q.Id
    ) AS TotalCommentScore,
    (
      SELECT
        COUNT(DISTINCT ph.UserId)
      FROM PostHistory AS ph
      WHERE
        ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS DistinctEditorsCount,
    (
      SELECT
        COUNT(*)
      FROM PostLinks AS pl
      WHERE
        pl.PostId = q.Id AND pl.LinkTypeId = 3
    ) AS DuplicateLinkCount
  FROM Posts AS q
  WHERE
    q.PostTypeId = 1
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadges,
    (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Class = 2
    ) AS SilverBadges,
    (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Class = 3
    ) AS BronzeBadges,
    COALESCE(
      (
        SELECT
          AVG(ra.Score)
        FROM RankedAnswers AS ra
        WHERE
          ra.OwnerUserId = u.Id AND ra.rn = 1
      ),
      0
    ) AS AvgAcceptedAnswerScore
  FROM Users AS u
)
SELECT
  qd.Title AS QuestionTitle,
  qd.QuestionCreationDate,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.FavoriteCount,
  ue.DisplayName AS QuestionOwnerDisplayName,
  ue.Reputation AS QuestionOwnerReputation,
  ue.GoldBadges,
  ue.SilverBadges,
  ue.BronzeBadges,
  ra.AnswerId AS BestAnswerId,
  ra.Score AS BestAnswerScore,
  (
    SELECT
      MAX(COALESCE(c.Score, 0))
    FROM Comments AS c
    WHERE
      c.PostId = ra.AnswerId
  ) AS BestAnswerMaxCommentScore,
  CASE
    WHEN qd.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN qd.FavoriteCount > 100 AND qd.AnswerCount > 10 THEN 'Hot'
    ELSE 'Active'
  END AS QuestionStatus,
  LOWER(REPLACE(qd.Tags, '><', ' ')) AS FormattedTags,
  (qd.QuestionViewCount * qd.FavoriteCount) / NULLIF(qd.AnswerCount, 0) AS EngagementRatio,
  COALESCE(ue.UserCreationDate, '1900-01-01') AS SafeUserCreationDate,
  qd.TotalCommentScore,
  qd.DistinctEditorsCount,
  qd.DuplicateLinkCount,
  COUNT(DISTINCT v.UserId) AS NumberOfVotersForQuestion,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
FROM QuestionDetails AS qd
LEFT OUTER JOIN UserEngagement AS ue
  ON qd.QuestionOwnerUserId = ue.UserId
LEFT OUTER JOIN RankedAnswers AS ra
  ON qd.QuestionId = ra.QuestionId AND ra.rn = 1
LEFT OUTER JOIN Votes AS v
  ON qd.QuestionId = v.PostId AND v.VoteTypeId IN (2, 3)
WHERE
  qd.QuestionCreationDate > '2023-01-01' AND qd.AnswerCount > 0
GROUP BY
  qd.Title,
  qd.QuestionCreationDate,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.FavoriteCount,
  ue.DisplayName,
  ue.Reputation,
  ue.GoldBadges,
  ue.SilverBadges,
  ue.BronzeBadges,
  ra.AnswerId,
  ra.Score,
  (
    SELECT
      MAX(COALESCE(c.Score, 0))
    FROM Comments AS c
    WHERE
      c.PostId = ra.AnswerId
  ),
  QuestionStatus,
  FormattedTags,
  EngagementRatio,
  SafeUserCreationDate,
  qd.TotalCommentScore,
  qd.DistinctEditorsCount,
  qd.DuplicateLinkCount
HAVING
  COUNT(v.UserId) > 10 OR qd.QuestionScore > 100
ORDER BY
  qd.QuestionScore DESC,
  qd.QuestionCreationDate ASC
LIMIT 100;