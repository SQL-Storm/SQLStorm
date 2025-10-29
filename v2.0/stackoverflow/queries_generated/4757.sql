-- {"query": "4757.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1320} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      MAX(p.CreationDate) AS LastPostCreationDate,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
      COUNT(DISTINCT rpe.PostId) AS EditedPostCount
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    LEFT JOIN RankedPostEdits AS rpe
      ON u.Id = rpe.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  PostInteraction AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      COUNT(DISTINCT c.Id) AS CommentCountPerPost,
      COUNT(DISTINCT v.Id) AS VoteCountPerPost,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      MAX(p.LastActivityDate) AS LastPostActivityDate,
      (
        SELECT
          COUNT(*)
        FROM PostLinks AS pl
        WHERE
          pl.PostId = p.Id AND pl.LinkTypeId = 3
      ) AS DuplicateLinkCount
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
    GROUP BY
      p.Id,
      p.Title,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate
  )
SELECT
  ua.DisplayName AS UserDisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.CommentCount AS UserCommentCount,
  ua.GoldBadgeCount,
  ua.SilverBadgeCount,
  ua.BronzeBadgeCount,
  ua.EditedPostCount,
  pi.Title AS PostTitle,
  pi.PostCreationDate,
  pi.Score AS PostScore,
  pi.ViewCount AS PostViewCount,
  pi.AnswerCount AS PostAnswerCount,
  pi.CommentCountPerPost AS PostComments,
  pi.VoteCountPerPost,
  pi.UpVoteCount,
  pi.DownVoteCount,
  pi.FavoriteCount AS PostFavoriteCount,
  pi.DuplicateLinkCount,
  pi.LastPostActivityDate,
  COALESCE(ua.DisplayName, 'Deleted User') AS DisplayNameOrPlaceholder,
  CASE
    WHEN pi.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN pi.Score > 100 THEN 'High Score'
    WHEN pi.ViewCount > 10000 THEN 'High View Count'
    ELSE 'Normal'
  END AS PostStatus,
  CASE
    WHEN TIMESTAMPDIFF(DAY, ua.UserCreationDate, NOW()) < 365 THEN 'New User'
    WHEN TIMESTAMPDIFF(DAY, ua.UserCreationDate, NOW()) BETWEEN 365 AND 365 * 5 THEN 'Established User'
    ELSE 'Veteran User'
  END AS UserTenureCategory,
  CONCAT(ua.DisplayName, ' - ', pi.Title) AS UserAndPost,
  CASE
    WHEN pi.UpVoteCount > pi.DownVoteCount * 2 THEN 'Positive Sentiment'
    WHEN pi.DownVoteCount > pi.UpVoteCount * 2 THEN 'Negative Sentiment'
    ELSE 'Neutral Sentiment'
  END AS VoteSentiment
FROM UserActivity AS ua
FULL OUTER JOIN PostInteraction AS pi
  ON ua.UserId = pi.OwnerUserId
WHERE
  ua.Reputation > 1000
  OR pi.Score > 50
ORDER BY
  ua.Reputation DESC,
  pi.PostScore DESC
LIMIT 100;
