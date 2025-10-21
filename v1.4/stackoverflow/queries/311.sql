-- {"query": "311.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20996} 
WITH
Base AS (
  SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Unknown') AS DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(u.Location, '') AS Location,
    COALESCE(u.AboutMe, '') AS AboutMe,
    COUNT(p.Id) AS PostCountAll,
    COALESCE(SUM(p.Score), 0) AS ScoreSumAll,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesAll,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesAll,
    COALESCE(MAX(p.LastActivityDate), NULL) AS LastActivityDateAll,
    COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadgesAll,
    COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadgesAll,
    COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadgesAll
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe
),
EngagementScore AS (
  SELECT
    b.UserId,
    b.DisplayName,
    b.Reputation,
    b.CreationDate AS CreationDate,
    b.LastAccessDate,
    b.Location,
    b.PostCountAll,
    b.ScoreSumAll,
    b.UpVotesAll,
    b.DownVotesAll,
    b.GoldBadgesAll,
    b.SilverBadgesAll,
    b.BronzeBadgesAll,
    COALESCE((
      SELECT p.Title
      FROM Posts p
      WHERE p.OwnerUserId = b.UserId
      ORDER BY p.CreationDate DESC, p.Id DESC
      LIMIT 1
    ), '(no posts)') AS MostRecentPostTitle,
    (
      SELECT p.CreationDate
      FROM Posts p
      WHERE p.OwnerUserId = b.UserId
      ORDER BY p.CreationDate DESC, p.Id DESC
      LIMIT 1
    ) AS MostRecentPostDate,
    (b.ScoreSumAll * 7
     + b.UpVotesAll * 3
     - b.DownVotesAll * 2
     + b.GoldBadgesAll * 10
     + b.SilverBadgesAll * 5
     + b.BronzeBadgesAll) AS EngagementScore,
    ROW_NUMBER() OVER (ORDER BY b.Reputation DESC, b.PostCountAll DESC) AS RepRank
  FROM Base b
)
SELECT *
FROM (
  SELECT
    UserId,
    DisplayName,
    Reputation,
    CreationDate,
    LastAccessDate,
    Location,
    PostCountAll,
    ScoreSumAll,
    UpVotesAll,
    DownVotesAll,
    GoldBadgesAll,
    SilverBadgesAll,
    BronzeBadgesAll,
    MostRecentPostTitle,
    MostRecentPostDate,
    EngagementScore,
    RepRank
  FROM EngagementScore
  ORDER BY EngagementScore DESC
  LIMIT 50
) AS TopEngagement
UNION ALL
SELECT *
FROM (
  SELECT
    UserId,
    DisplayName,
    Reputation,
    CreationDate,
    LastAccessDate,
    Location,
    PostCountAll,
    ScoreSumAll,
    UpVotesAll,
    DownVotesAll,
    GoldBadgesAll,
    SilverBadgesAll,
    BronzeBadgesAll,
    MostRecentPostTitle,
    MostRecentPostDate,
    EngagementScore,
    RepRank
  FROM EngagementScore
  ORDER BY PostCountAll DESC
  LIMIT 50
) AS TopActivity
ORDER BY EngagementScore DESC
LIMIT 100;