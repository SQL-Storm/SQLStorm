-- {"query": "392.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 26304} 
WITH
  UserBase AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.LastAccessDate,
      COALESCE(u.Location, '') AS UserLocation,
      u.AccountId
    FROM Users u
  ),
  PostStats AS (
    SELECT
      p.OwnerUserId AS UserId,
      COUNT(*) AS PostCount,
      MAX(p.LastActivityDate) AS LastActivityDate,
      SUM(p.Score) AS TotalScore
    FROM Posts p
    GROUP BY p.OwnerUserId
  ),
  VoteStats AS (
    SELECT
      v.UserId AS UserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM Votes v
    GROUP BY v.UserId
  ),
  BadgeStats AS (
    SELECT
      b.UserId AS UserId,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
  ),
  TagStats AS (
    SELECT
      p.OwnerUserId AS UserId,
      SUM(COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1), 0)) AS TotalTagCount
    FROM Posts p
    GROUP BY p.OwnerUserId
  ),
  LastPosts AS (
    SELECT
      p.OwnerUserId AS UserId,
      p.Title,
      p.LastActivityDate,
      p.Score,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
    FROM Posts p
  )
SELECT
  ub.UserId,
  ub.DisplayName,
  ub.Reputation,
  ub.LastAccessDate,
  ub.UserLocation,
  COALESCE(ps.PostCount, 0) AS PostCount,
  COALESCE(ps.TotalScore, 0) AS TotalScore,
  COALESCE(vs.UpVotesGiven, 0) AS UpVotesGiven,
  COALESCE(vs.DownVotesGiven, 0) AS DownVotesGiven,
  COALESCE(bs.GoldBadges, 0) AS GoldBadges,
  COALESCE(bs.SilverBadges, 0) AS SilverBadges,
  COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
  COALESCE(ts.TotalTagCount, 0) AS TotalTagCount,
  (SELECT MAX(p2.LastActivityDate) FROM Posts p2 WHERE p2.OwnerUserId = ub.UserId) AS LastPostDate,
  (
    SELECT json_agg(json_build_object('title', lp.Title, 'date', lp.LastActivityDate, 'score', lp.Score))
    FROM LastPosts lp
    WHERE lp.UserId = ub.UserId AND lp.rn <= 3
  ) AS LastThreePosts
FROM UserBase ub
LEFT JOIN PostStats ps ON ps.UserId = ub.UserId
LEFT JOIN VoteStats vs ON vs.UserId = ub.UserId
LEFT JOIN BadgeStats bs ON bs.UserId = ub.UserId
LEFT JOIN TagStats ts ON ts.UserId = ub.UserId
ORDER BY ub.Reputation DESC
LIMIT 200;