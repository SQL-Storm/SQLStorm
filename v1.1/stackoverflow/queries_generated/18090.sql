-- {"query": "18090.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1075} 

WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(p.Score) AS TotalScore,
      AVG(p.ViewCount) AS AvgViewCount,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  CommentActivity AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserBadgeCounts AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadgeCount,
      COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadgeCount,
      COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadgeCount
    FROM Badges AS b
    GROUP BY
      b.UserId
  ),
  HighActivityUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      ups.PostCount,
      ups.TotalScore,
      ups.AvgViewCount,
      ca.CommentCount,
      ca.AvgCommentScore,
      ubc.GoldBadgeCount,
      ubc.SilverBadgeCount,
      ubc.BronzeBadgeCount,
      DATEDIFF(
        day,
        u.CreationDate,
        GETDATE()
      ) AS AccountAgeDays,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, ups.PostCount DESC) AS RankByReputationAndPosts
    FROM Users AS u
    LEFT JOIN UserPostStats AS ups
      ON u.Id = ups.OwnerUserId
    LEFT JOIN CommentActivity AS ca
      ON u.Id = ca.UserId
    LEFT JOIN UserBadgeCounts AS ubc
      ON u.Id = ubc.UserId
    WHERE
      u.Id NOT IN (
        SELECT
          UserId
        FROM PostHistory
        WHERE
          PostHistoryTypeId = 12 /* Post Deleted */ AND UserId IS NOT NULL
      )
      AND u.Views > 1000
      AND ups.PostCount > 50
      AND ca.CommentCount > 100
  )
SELECT
  hau.DisplayName,
  hau.Reputation,
  hau.AccountAgeDays,
  hau.PostCount,
  hau.TotalScore,
  hau.AvgViewCount,
  hau.CommentCount,
  hau.AvgCommentScore,
  hau.GoldBadgeCount,
  hau.SilverBadgeCount,
  hau.BronzeBadgeCount,
  CASE
    WHEN hau.AvgViewCount > 10000 THEN 'High Engagement'
    WHEN hau.AvgViewCount > 1000 THEN 'Medium Engagement'
    ELSE 'Low Engagement'
  END AS EngagementLevel,
  LAG(hau.DisplayName, 1, 'No Previous User') OVER (ORDER BY hau.RankByReputationAndPosts) AS PreviousUserDisplayName,
  LEAD(hau.DisplayName, 1, 'No Next User') OVER (ORDER BY hau.RankByReputationAndPosts) AS NextUserDisplayName,
  CASE
    WHENhau.GoldBadgeCount > 5 THEN 'Elite'
    WHEN hau.SilverBadgeCount > 10 THEN 'Distinguished'
    ELSE 'Regular'
  END AS BadgeTier
FROM HighActivityUsers AS hau
WHERE
  hau.RankByReputationAndPosts <= 50
UNION ALL
SELECT
  '--- Total Averages ---',
  AVG(CAST(hau.Reputation AS NUMERIC)),
  AVG(CAST(hau.AccountAgeDays AS NUMERIC)),
  AVG(CAST(hau.PostCount AS NUMERIC)),
  AVG(CAST(hau.TotalScore AS NUMERIC)),
  AVG(CAST(hau.AvgViewCount AS NUMERIC)),
  AVG(CAST(hau.CommentCount AS NUMERIC)),
  AVG(CAST(hau.AvgCommentScore AS NUMERIC)),
  AVG(CAST(hau.GoldBadgeCount AS NUMERIC)),
  AVG(CAST(hau.SilverBadgeCount AS NUMERIC)),
  AVG(CAST(hau.BronzeBadgeCount AS NUMERIC)),
  NULL,
  NULL,
  NULL
FROM HighActivityUsers AS hau
WHERE
  hau.RankByReputationAndPosts <= 50;
