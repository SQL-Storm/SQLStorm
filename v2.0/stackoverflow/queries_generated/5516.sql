-- {"query": "5516.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 768} 
WITH
Signals AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AboutMe,
    u.WebsiteUrl,
    u.AccountId,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswerCount,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views,
    u.UpVotes, u.DownVotes, u.Location, u.AboutMe, u.WebsiteUrl,
    u.AccountId
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TagUsage
  FROM Tags t
  GROUP BY t.TagName
  ORDER BY TagUsage DESC
  LIMIT 100
),
Activity AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) AS PostsCreated,
    SUM(p.ViewCount) AS TotalViews,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswers
  FROM Posts p
  GROUP BY p.OwnerUserId
),
RecentEdits AS (
  SELECT
    ph.UserId,
    ph.PostId,
    ph.CreationDate AS EditDate,
    ph.PostHistoryTypeId,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,8,9,16,36)
),
ComplexQuery AS (
  SELECT
    s.UserId,
    s.DisplayName,
    s.Reputation,
    s.LastActivityDate,
    a.PostsCreated,
    a.TotalViews,
    a.TotalAnswers,
    t.TagName
  FROM Signals s
  LEFT JOIN Activity a ON a.UserId = s.UserId
  LEFT JOIN RecentEdits re ON re.UserId = s.UserId
  LEFT JOIN (
    SELECT UserId, MAX(EditDate) AS MaxEdit
    FROM RecentEdits
    GROUP BY UserId
  ) AS le ON le.UserId = s.UserId
  LEFT JOIN TopTags t ON t.TagUsage IS NOT NULL
  WHERE s.Reputation > 1000
    OR s.LastActivityDate > NOW() - INTERVAL '180 days'
)
SELECT
  cu.UserId,
  cu.DisplayName,
  cu.Reputation,
  cu.LastActivityDate,
  cu.PostsCreated,
  cu.TotalViews,
  cu.TotalAnswers,
  cu.TagName,
  CASE
    WHEN cu.TotalViews > 10000 THEN 'Power Engager'
    WHEN cu.TotalViews BETWEEN 1000 AND 9999 THEN 'Active'
    ELSE 'Casual'
  END AS ActivityTier,
  CONCAT('[', cu.TotalViews, '/', cu.TotalAnswers, ']') AS ViewAnswerRatio,
  CASE
    WHEN cu.Reputation IS NULL THEN NULL
    ELSE ROUND((cu.Reputation * 1.0) / NULLIF(cu.TotalViews, 0), 4)
  END AS ReputationPerView
FROM ComplexQuery cu
ORDER BY cu.Reputation DESC NULLS LAST, cu.TotalViews DESC NULLS LAST
LIMIT 200;