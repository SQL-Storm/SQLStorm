-- {"query": "5753.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 752} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.AccountId,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.Date AS BadgeDate,
    b.TagBased,
    v.VoteTypeId,
    vt.Name AS VoteTypeName,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.CreationDate >= NOW() - INTERVAL '365 days'
    AND p.PostTypeId IN (1, 2) -- limit to Questions (1) and Answers (2)
),
Aggregated AS (
  SELECT
    rp.OwnerUserId AS UserId,
    COUNT(DISTINCT rp.PostId) AS PostCount,
    SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(rp.Score) AS TotalScore,
    SUM(rp.ViewCount) AS TotalViews,
    COUNT(DISTINCT rp.TagBased) AS TagBasedCount,
    MAX(rp.CreationDate) AS LastPostDate,
    STRING_AGG(DISTINCT rp.Tags, ',') AS AllTags
  FROM RankedPosts rp
  GROUP BY rp.OwnerUserId
),
TopContributors AS (
  SELECT
    a.UserId,
    a.PostCount,
    a.QuestionCount,
    a.AnswerCount,
    a.TotalScore,
    a.TotalViews,
    a.LastPostDate,
    a.AllTags,
    ROW_NUMBER() OVER (ORDER BY a.TotalScore DESC, a.TotalViews DESC, a.PostCount DESC) AS rn
  FROM Aggregated a
)
SELECT
  tc.UserId,
  tc.PostCount,
  tc.QuestionCount,
  tc.AnswerCount,
  tc.TotalScore,
  tc.TotalViews,
  tc.LastPostDate,
  tc.AllTags,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = tc.UserId) AS PostTotalByUser,
  (SELECT AVG(r.Reputation) FROM Users r WHERE r.Id = tc.UserId) AS AvgUserReputation,
  (SELECT MAX(e.Date) FROM (SELECT CreationDate AS Date FROM Posts WHERE OwnerUserId = tc.UserId UNION ALL SELECT Date FROM Badges WHERE UserId = tc.UserId) e) AS MostRecentActivity
FROM TopContributors tc
WHERE tc.rn = 1
ORDER BY tc.TotalScore DESC, tc.TotalViews DESC
LIMIT 10;