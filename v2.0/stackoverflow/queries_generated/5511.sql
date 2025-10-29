-- {"query": "5511.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1050} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  u.Location,
  COALESCE(u.AboutMe, '') AS AboutMe,
  COALESCE(u.Views, 0) AS Views,
  COALESCE(u.UpVotes, 0) AS UpVotes,
  COALESCE(u.DownVotes, 0) AS DownVotes,
  u.ProfileImageUrl,
  u.EmailHash,
  u.AccountId,
  COALESCE(bg.GoldBadges, 0) AS GoldBadges,
  COALESCE(bs.SilverBadges, 0) AS SilverBadges,
  COALESCE(bb.BronzeBadges, 0) AS BronzeBadges,
  p1.AnswerCount AS QuestionAnswerCount,
  p2.CommentCount AS QuestionCommentCount,
  v1.VoteUpCount,
  v2.VoteDownCount,
  cl.ClosedQuestionsRatio,
  wl.LastWikiEditDate,
  wl.WikiEditCount,
  wl.TagEditCount
FROM
  Users u
  LEFT JOIN (
    SELECT
      OwnerUserId,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY OwnerUserId
  ) AS bg ON bg.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      OwnerUserId,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY OwnerUserId
  ) AS bs ON bs.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      OwnerUserId,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY OwnerUserId
  ) AS bb ON bb.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      OwnerUserId,
      COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) p1 ON p1.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      OwnerUserId,
      COUNT(*) AS CommentCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) p2 ON p2.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      UserId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS VoteUpCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS VoteDownCount
    FROM Votes
    GROUP BY UserId
  ) v1 ON v1.UserId = u.Id
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(*) AS UpvoteComments
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
  ) v2 ON v2.PostId = (SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 LIMIT 1)
  LEFT JOIN (
    SELECT
      1 AS dummy,
      AVG(COALESCE(ClosedCount, 0)) AS ClosedQuestionsRatio
    FROM (
      SELECT
        SUM(CASE WHEN ClosedDate IS NOT NULL THEN 1 ELSE 0 END) OVER ()::float / NULLIF(COUNT(*) OVER (), 0) AS ClosedCount
      FROM Posts
      WHERE PostTypeId = 1
    ) AS sub
  ) cl ON 1=1
  LEFT JOIN (
    SELECT
      OwnerUserId,
      MAX(LastEditDate) AS LastWikiEditDate,
      SUM(CASE WHEN PostTypeId IN (4,5) THEN 1 ELSE 0 END) AS WikiEditCount,
      SUM(CASE WHEN PostTypeId IN (4,5) THEN 1 ELSE 0 END) AS TagEditCount
    FROM Posts
    WHERE PostTypeId IN (4,5)
    GROUP BY OwnerUserId
  ) wl ON wl.OwnerUserId = u.Id
WHERE
  u.AccountId IS NOT NULL
ORDER BY
  u.Reputation DESC
LIMIT 100;