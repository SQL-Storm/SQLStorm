-- {"query": "4113.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1455} 

WITH
  TopPosters AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS PostCount
    FROM Posts
    WHERE
      PostTypeId = 1 -- Questions
      AND CreationDate >= DATE('now', '-1 year')
    GROUP BY
      OwnerUserId
    ORDER BY
      PostCount DESC
    LIMIT 10
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
      MAX(p.CreationDate) AS LastQuestionDate,
      AVG(p.Score) AS AverageQuestionScore,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId AND c.CreationDate >= p.CreationDate AND c.CreationDate < p.CreationDate + INTERVAL '1 day' -- Associate comments with posts made on the same day
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    WHERE
      u.Id IN (SELECT OwnerUserId FROM TopPosters)
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  AnswerMetrics AS (
    SELECT
      p.OwnerUserId,
      COUNT(a.Id) AS AnswerCount,
      AVG(a.Score) AS AverageAnswerScore,
      SUM(CASE WHEN a.IsAccepted = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerCount -- Assuming 'IsAccepted' column exists for answers, otherwise this needs to be derived from Posts.AcceptedAnswerId logic
    FROM Posts AS p
    JOIN Posts AS a
      ON p.Id = a.ParentId
    WHERE
      p.PostTypeId = 1 -- Questions
      AND p.CreationDate >= DATE('now', '-1 year')
      AND a.PostTypeId = 2 -- Answers
    GROUP BY
      p.OwnerUserId
  ),
  CommunityEngagement AS (
    SELECT
      ph.UserId,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVotesCast, -- Post Closed
      COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenVotesCast, -- Post Reopened
      COUNT(CASE WHEN ph.PostHistoryTypeId = 16 THEN 1 END) AS CommunityOwnedEvents
    FROM PostHistory AS ph
    WHERE
      ph.UserId IS NOT NULL
      AND ph.CreationDate >= DATE('now', '-1 year')
    GROUP BY
      ph.UserId
  ),
  PostLinkAnalysis AS (
    SELECT
      pl.PostId,
      COUNT(DISTINCT COALESCE(pl_related.Id, 0)) AS DuplicateLinksToOtherPosts,
      COUNT(DISTINCT COALESCE(pl_linked.Id, 0)) AS LinkedToOtherPosts
    FROM PostLinks AS pl
    LEFT JOIN PostLinks AS pl_related
      ON pl.PostId = pl_related.RelatedPostId AND pl_related.LinkTypeId = 3 -- Linked PostId is a duplicate of RelatedPostId
    LEFT JOIN PostLinks AS pl_linked
      ON pl.PostId = pl_linked.PostId AND pl_linked.LinkTypeId = 1 -- Linked PostId contains a link to RelatedPostId
    WHERE
      pl.CreationDate >= DATE('now', '-1 year')
    GROUP BY
      pl.PostId
  )
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.QuestionCount,
  COALESCE(am.AnswerCount, 0) AS TotalAnswersPosted,
  COALESCE(am.AverageAnswerScore, 0) AS AvgAnswerScore,
  COALESCE(am.AcceptedAnswerCount, 0) AS AcceptedAnswers,
  ua.CommentCount,
  ua.LastQuestionDate,
  ua.AverageQuestionScore,
  ua.GoldBadges,
  ua.SilverBadges,
  ua.BronzeBadges,
  COALESCE(ce.CloseVotesCast, 0) AS CloseVotes,
  COALESCE(ce.ReopenVotesCast, 0) AS ReopenVotes,
  COALESCE(ce.CommunityOwnedEvents, 0) AS CommunityOwnedCount,
  COALESCE(pla.DuplicateLinksToOtherPosts, 0) AS PostsLinkedAsDuplicates,
  COALESCE(pla.LinkedToOtherPosts, 0) AS PostsLinkingToOthers,
  CASE
    WHEN ua.Reputation > 100000 THEN 'Titan'
    WHEN ua.Reputation BETWEEN 50000 AND 100000 THEN 'Expert'
    WHEN ua.Reputation BETWEEN 10000 AND 49999 THEN 'Advanced'
    WHEN ua.Reputation BETWEEN 1000 AND 9999 THEN 'Proficient'
    ELSE 'Novice'
  END AS ReputationTier,
  SUBSTRING(ua.DisplayName FROM 1 FOR 3) || '***' AS MaskedDisplayName, -- Simple string manipulation for masking
  CASE
    WHEN ua.LastQuestionDate < DATE('now', '-6 months') THEN 'Inactive Lately'
    ELSE 'Active Lately'
  END AS ActivityStatus
FROM UserActivity AS ua
LEFT JOIN AnswerMetrics AS am
  ON ua.UserId = am.OwnerUserId
LEFT JOIN CommunityEngagement AS ce
  ON ua.UserId = ce.UserId
LEFT JOIN PostLinkAnalysis AS pla
  ON ua.UserId = pla.PostId -- Assuming PostId in PostLinkAnalysis corresponds to OwnerUserId for questions
WHERE
  (ua.GoldBadges + ua.SilverBadges + ua.BronzeBadges) > 5 -- Filter for users with at least some badges
  OR ua.Reputation > 50000; -- OR users with high reputation
