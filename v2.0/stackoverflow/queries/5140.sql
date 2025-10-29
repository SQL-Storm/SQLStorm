-- {"query": "5140.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 828} 
WITH UserStats AS (
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
    u.WebsiteUrl,
    u.AboutMe,
    COALESCE(b.TotalBadges, 0) AS TotalBadges
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.OwnerUserId,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
RecentActivity AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.ViewCount,
    q.Score,
    q.CreationDate,
    q.AnswerCount,
    q.CommentCount,
    LAG(q.Title) OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate) AS PrevTitle,
    LEAD(q.Title) OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate) AS NextTitle
  FROM (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.ViewCount,
      p.Score,
      p.CreationDate,
      p.AnswerCount,
      p.CommentCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (SELECT MIN(CreationDate) FROM Posts)
  ) q
),
Combined AS (
  SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.CreationDate AS UserCreationDate,
    us.LastAccessDate,
    us.Location,
    us.WebsiteUrl,
    us.TotalBadges,
    ra.PostId AS RecentQuestionId,
    ra.Title AS RecentQuestionTitle,
    ra.ViewCount AS RecentQuestionViews,
    ra.Score AS RecentQuestionScore,
    ra.CreationDate AS RecentQuestionDate,
    ra.CommentCount AS RecentQuestionComments,
    ra.AnswerCount AS RecentQuestionAnswers,
    ra.PrevTitle,
    ra.NextTitle,
    ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY ra.CreationDate DESC) AS rn
  FROM UserStats us
  LEFT JOIN (
    SELECT
      tq.PostId,
      tq.Title,
      tq.OwnerUserId,
      tq.ViewCount,
      tq.Score,
      tq.CreationDate,
      tq.CommentCount,
      tq.AnswerCount,
      tq.PrevTitle,
      tq.NextTitle
    FROM RecentActivity tq
  ) ra ON ra.OwnerUserId = us.UserId
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.UserCreationDate,
  c.LastAccessDate,
  c.Location,
  c.WebsiteUrl,
  c.TotalBadges,
  c.RecentQuestionId,
  c.RecentQuestionTitle,
  c.RecentQuestionViews,
  c.RecentQuestionScore,
  c.RecentQuestionDate,
  c.RecentQuestionComments,
  c.RecentQuestionAnswers,
  c.PrevTitle,
  c.NextTitle
FROM Combined c
WHERE c.rn = 1
ORDER BY c.Reputation DESC NULLS LAST, c.RecentQuestionViews DESC NULLS LAST
LIMIT 100;