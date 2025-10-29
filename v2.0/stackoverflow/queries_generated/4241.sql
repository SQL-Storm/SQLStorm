-- {"query": "4241.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1108} 

WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= DATE('now', '-30 day')
  ),
  TopAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS answer_rank
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2
  ),
  QuestionActivity AS (
    SELECT
      ph.PostId AS QuestionId,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVoteCount,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 19 THEN 1 END) AS ProtectVoteCount,
      MAX(CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.CreationDate ELSE NULL END) AS CommunityOwnedDate
    FROM PostHistory AS ph
    WHERE
      ph.PostId IN (SELECT QuestionId FROM RecentQuestions)
    GROUP BY
      ph.PostId
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
      COUNT(c.Id) AS CommentCount
    FROM Users AS u
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    WHERE
      u.Id IN (
        SELECT
          OwnerUserId
        FROM RecentQuestions
      )
      OR u.Id IN (
        SELECT
          OwnerUserId
        FROM TopAnswers
      )
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  )
SELECT
  rq.Title AS QuestionTitle,
  rq.QuestionCreationDate,
  rq.QuestionScore,
  rq.AnswerCount,
  rq.FavoriteCount,
  rq.QuestionViewCount,
  ue.DisplayName AS OwnerDisplayName,
  ue.Reputation,
  ue.GoldBadges,
  ue.SilverBadges,
  ue.BronzeBadges,
  ta.AnswerScore AS BestAnswerScore,
  ta.AnswerCreationDate AS BestAnswerCreationDate,
  qa.CloseVoteCount,
  qa.ProtectVoteCount,
  CASE
    WHEN qa.CommunityOwnedDate IS NOT NULL THEN 'Yes'
    ELSE 'No'
  END AS IsCommunityOwned,
  CASE
    WHEN rq.QuestionScore > 50 AND rq.AnswerCount > 10 THEN 'Popular'
    WHEN rq.QuestionScore < 0 THEN 'Controversial'
    WHEN rq.FavoriteCount > 5 THEN 'Bookmarked'
    ELSE 'Standard'
  END AS QuestionStatus,
  UPPER(SUBSTRING(ue.DisplayName, 1, 3)) || '-' || CAST(ue.Reputation AS VARCHAR) AS UserIdentifier,
  COALESCE(ue.TotalUpVotes, 0) + COALESCE(ue.TotalDownVotes, 0) AS TotalVotesCast
FROM RecentQuestions AS rq
LEFT JOIN TopAnswers AS ta
  ON rq.QuestionId = ta.QuestionId AND ta.answer_rank = 1
LEFT JOIN UserEngagement AS ue
  ON rq.OwnerUserId = ue.UserId
LEFT JOIN QuestionActivity AS qa
  ON rq.QuestionId = qa.QuestionId
WHERE
  rq.rn <= 100
  AND (ue.Reputation IS NULL OR ue.Reputation > 1000)
  AND rq.AnswerCount > 0
ORDER BY
  rq.QuestionScore DESC,
  rq.QuestionCreationDate DESC
LIMIT 50;
