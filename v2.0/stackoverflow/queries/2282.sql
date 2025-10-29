-- {"query": "2282.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1338}
WITH RECURSIVE RecursivePosts AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.AcceptedAnswerId, p.Title, p.Tags, p.CreationDate,
      0 AS Level
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    
    UNION ALL
    
    SELECT c.Id, c.PostTypeId, c.OwnerUserId, c.Score, c.ViewCount, c.AcceptedAnswerId, c.Title, c.Tags, c.CreationDate,
      rp.Level + 1
    FROM Posts c
    JOIN RecursivePosts rp ON c.ParentId = rp.Id
    WHERE c.PostTypeId = 2
),
UserBadgeCounts AS (
    SELECT b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
LatestPostHistory AS (
    SELECT ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
),
PostCloseInfo AS (
    SELECT lph.PostId, cr.Name AS CloseReason, COUNT(*) AS CloseVotes
    FROM LatestPostHistory lph
    LEFT JOIN CloseReasonTypes cr ON cr.Id = CAST(lph.Comment AS integer)
    WHERE lph.PostHistoryTypeId = 10
    GROUP BY lph.PostId, cr.Name
),
UserActivityWindow AS (
    SELECT 
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
      COALESCE(SUM(p.Score),0) AS TotalPostScore,
      MAX(p.Score) AS HighestPostScore,
      MIN(p.Score) AS LowestPostScore,
      AVG(p.Score) AS AvgPostScore,
      COUNT(DISTINCT c.Id) AS CommentsMade,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesGiven,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(pb.GoldBadges) AS GoldBadges,
      MAX(pb.SilverBadges) AS SilverBadges,
      MAX(pb.BronzeBadges) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    LEFT JOIN UserBadgeCounts pb ON pb.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionAnswerStats AS (
    SELECT 
      q.Id AS QuestionId, q.Title, q.CreationDate AS QuestionDate, q.Tags, q.Score AS QuestionScore, q.ViewCount,
      a.Id AS AnswerId, a.OwnerUserId AS AnswerOwnerUserId, a.Score AS AnswerScore, a.CreationDate AS AnswerDate,
      RANK() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
),
HighActivityUsers AS (
    SELECT UserId
    FROM UserActivityWindow
    WHERE TotalPosts > 100 AND Reputation > 5000
),
DuplicatedLinks AS (
    SELECT pl.PostId, pl.RelatedPostId, pl.CreationDate, lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.LinkTypeId = 3
)
SELECT 
  uaw.UserId,
  uaw.DisplayName,
  uaw.Reputation,
  uaw.TotalPosts,
  uaw.Questions,
  uaw.Answers,
  uaw.TotalPostScore,
  uaw.HighestPostScore,
  uaw.LowestPostScore,
  uaw.AvgPostScore,
  uaw.CommentsMade,
  uaw.UpVotesGiven,
  uaw.GoldBadges,
  uaw.SilverBadges,
  uaw.BronzeBadges,
  qa.QuestionId,
  qa.Title,
  qa.QuestionScore,
  qa.ViewCount,
  qa.AnswerId,
  qa.AnswerOwnerUserId,
  qa.AnswerScore,
  qa.AnswerRank,
  pc.CloseReason,
  pc.CloseVotes,
  dl.RelatedPostId AS DuplicateOfPost,
  ( COALESCE(uaw.DisplayName, 'NoUser')
    || ' | '
    || 'Posts: ' || COALESCE(CAST(uaw.TotalPosts AS varchar), '0')
    || ' | ScoreAvg: ' || COALESCE(CAST(ROUND(COALESCE(uaw.AvgPostScore,0),2) AS varchar), '0')
    || ' | Gold Badges: ' || COALESCE(CAST(uaw.GoldBadges AS varchar), '0')
  ) AS UserSummary
FROM HighActivityUsers hau
JOIN UserActivityWindow uaw ON hau.UserId = uaw.UserId
LEFT JOIN QuestionAnswerStats qa ON qa.AnswerOwnerUserId = uaw.UserId AND qa.AnswerRank = 1
LEFT JOIN PostCloseInfo pc ON pc.PostId = qa.QuestionId
LEFT JOIN DuplicatedLinks dl ON dl.PostId = qa.QuestionId
WHERE (qa.QuestionScore > 10) OR (uaw.GoldBadges > 0)
ORDER BY uaw.Reputation DESC, qa.QuestionScore DESC NULLS LAST, qa.AnswerScore DESC NULLS LAST
LIMIT 100;