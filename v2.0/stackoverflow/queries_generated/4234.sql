-- {"query": "4234.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1517} 
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AverageScore,
      MAX(p.LastActivityDate) AS LastActiveDate
    FROM
      Posts AS p
    GROUP BY
      p.OwnerUserId
  ),
  UserBadgeCounts AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM
      Badges AS b
    GROUP BY
      b.UserId
  ),
  RecentEditDetails AS (
    SELECT
      rpe.UserId,
      rpe.PostId,
      rpe.CreationDate AS LastEditDate,
      p.Title AS PostTitle,
      p.PostTypeId,
      p.Score AS PostScore
    FROM
      RankedPostEdits AS rpe
    JOIN
      Posts AS p
      ON rpe.PostId = p.Id
    WHERE
      rpe.rn = 1
  ),
  UserActivitySummary AS (
    SELECT
      upa.OwnerUserId,
      upa.TotalPosts,
      upa.QuestionCount,
      upa.AnswerCount,
      upa.AverageScore,
      COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
      COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
      COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
      COUNT(DISTINCT red.PostId) AS RecentEditsCount,
      MAX(red.LastEditDate) AS LastEditSubmitted
    FROM
      UserPostActivity AS upa
    LEFT JOIN
      UserBadgeCounts AS ubc
      ON upa.OwnerUserId = ubc.UserId
    LEFT JOIN
      RecentEditDetails AS red
      ON upa.OwnerUserId = red.UserId
    GROUP BY
      upa.OwnerUserId,
      upa.TotalPosts,
      upa.QuestionCount,
      upa.AnswerCount,
      upa.AverageScore,
      COALESCE(ubc.GoldBadges, 0),
      COALESCE(ubc.SilverBadges, 0),
      COALESCE(ubc.BronzeBadges, 0)
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    WHEN INSTR(u.WebsiteUrl, 'stack') > 0 THEN 'Stack Exchange Site'
    ELSE 'External Website'
  END AS WebsiteType,
  uas.TotalPosts,
  uas.QuestionCount,
  uas.AnswerCount,
  uas.AverageScore,
  uas.GoldBadges,
  uas.SilverBadges,
  uas.BronzeBadges,
  uas.RecentEditsCount,
  uas.LastEditSubmitted,
  pht.Name AS LastPostHistoryTypeName,
  ph.Comment AS LastPostHistoryComment,
  ph.Text AS LastPostHistoryText,
  SUM(CASE WHEN c.Score > 5 THEN 1 ELSE 0 END) AS HighScoreCommentCount,
  MAX(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS IsPostClosed,
  CASE
    WHEN uas.TotalPosts > 1000 THEN 'Power User'
    WHEN uas.TotalPosts > 100 THEN 'Regular User'
    ELSE 'New User'
  END AS UserActivityLevel,
  CASE
    WHEN u.DownVotes > u.UpVotes * 2 THEN 'High Downvote Ratio'
    WHEN u.UpVotes > u.DownVotes * 2 THEN 'High Upvote Ratio'
    ELSE 'Balanced Votes'
  END AS VoteRatioCategory
FROM
  Users AS u
JOIN
  UserActivitySummary AS uas
  ON u.Id = uas.OwnerUserId
LEFT JOIN
  PostHistory AS ph
  ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36) -- Join on recent history types
LEFT JOIN
  PostHistoryTypes AS pht
  ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN
  Comments AS c
  ON u.Id = c.UserId
LEFT JOIN
  Posts AS p
  ON u.Id = p.OwnerUserId
WHERE
  u.Id IN (
    SELECT DISTINCT
      OwnerUserId
    FROM
      Posts
    WHERE
      CreationDate BETWEEN DATE('now', '-365 day') AND DATE('now')
  )
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  WebsiteType,
  uas.TotalPosts,
  uas.QuestionCount,
  uas.AnswerCount,
  uas.AverageScore,
  uas.GoldBadges,
  uas.SilverBadges,
  uas.BronzeBadges,
  uas.RecentEditsCount,
  uas.LastEditSubmitted,
  pht.Name,
  ph.Comment,
  ph.Text,
  UserActivityLevel,
  VoteRatioCategory
HAVING
  COUNT(DISTINCT ph.Id) > 0 OR uas.TotalPosts > 0
ORDER BY
  u.Reputation DESC,
  uas.LastActiveDate DESC;