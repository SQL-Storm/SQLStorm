-- {"query": "5016.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 941} 
WITH
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
    COUNT(CASE WHEN t.Name = 'AcceptedByOriginator' THEN 1 END) AS AcceptedByOriginatorVotes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes t ON t.Id = v.VoteTypeId
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
  GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Tags, p.LastActivityDate
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AccountId,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location, u.AccountId
),
ComplexReport AS (
  SELECT
    q.Id AS QuestionId,
    q.Title AS QuestionTitle,
    q.CreationDate AS AskedOn,
    q.Score AS QuestionScore,
    q.ViewCount AS Views,
    q.Tags,
    ra.RecentActivityDate AS LastActive,
    ua.UserId,
    ua.DisplayName AS UserDisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    sz.TotalSubmissions,
    sz.AverageAnswerCount,
    v.UpVotes,
    v.DownVotes,
    v.AcceptedByOriginatorVotes
  FROM TopQuestions v
  JOIN LATERAL (
    SELECT p.LastActivityDate AS RecentActivityDate
  ) ra ON true
  LEFT JOIN Posts q ON q.Id = v.PostId
  LEFT JOIN RecentActivity ra2 ON ra2.PostId = q.Id
  LEFT JOIN UserStats ua ON ua.UserId = q.OwnerUserId
  LEFT JOIN (
    SELECT
      p.Id,
      COUNT(a.Id) AS TotalSubmissions,
      AVG(a.AnswerCount) AS AverageAnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
  ) sz ON sz.Id = q.Id
  WHERE q.PostTypeId = 1
)
SELECT
  QuestionId,
  QuestionTitle,
  AskedOn,
  QuestionScore,
  Views,
  Tags,
  LastActive,
  UserId,
  UserDisplayName,
  Reputation,
  GoldBadges,
  SilverBadges,
  BronzeBadges,
  TotalSubmissions,
  AverageAnswerCount,
  UpVotes,
  DownVotes,
  AcceptedByOriginatorVotes
FROM ComplexReport
ORDER BY LastActive DESC
LIMIT 100;