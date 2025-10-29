-- {"query": "5464.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 742} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.AccountId,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    (SELECT STRING_AGG(vt.Name, ',') FROM Votes v
      JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
      WHERE v.PostId = p.Id
        AND vt.Id IN (2,3,10,11,12)) AS VoteSummary,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= TIMESTAMP '2023-01-01'
),
recent_activity AS (
  SELECT
    rp.*,
    LAG(rp.LastActivityDate) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.LastActivityDate) AS PrevActivity
  FROM ranked_posts rp
  WHERE rp.rn_owner = 1
),
complex_filters AS (
  SELECT
    ra.*,
    CASE
      WHEN ra.Score > 0 THEN 'positive'
      WHEN ra.Score < 0 THEN 'negative'
      ELSE 'neutral'
    END AS ScoreMood,
    CASE
      WHEN ra.ViewCount > 1000 THEN TRUE
      ELSE FALSE
    END AS HighlyViewed,
    (SELECT COUNT(*) FROM Posts c WHERE c.ParentId = ra.Id AND c.PostTypeId = 2) AS ChildAnswers
  FROM recent_activity ra
  LEFT JOIN PostLinks pl ON pl.PostId = ra.Id
  LEFT JOIN Tags t ON t.WikiPostId = ra.Id OR t.ExcerptPostId = ra.Id
  WHERE ra.LastEditDate IS NULL
     OR ra.LastEditDate > (SELECT AVG(LastEditDate) FROM Posts)
)
SELECT
  cf.Id,
  cf.Title,
  cf.PostTypeId,
  cf.OwnerUserId,
  cf.CreationDate,
  cf.LastActivityDate,
  cf.Score,
  cf.ViewCount,
  cf.Tags,
  cf.AnswerCount,
  cf.CommentCount,
  cf.FavoriteCount,
  cf.ParentId,
  cf.AcceptedAnswerId,
  cf.Body,
  cf.LastEditorUserId,
  cf.LastEditDate,
  cf.ContentLicense,
  cf.Reputation,
  cf.DisplayName,
  cf.Location,
  cf.AccountId,
  cf.Views,
  cf.UpVotes,
  cf.DownVotes,
  cf.BadgeName,
  cf.BadgeDate,
  cf.BadgeClass,
  cf.VoteSummary,
  cf.ScoreMood,
  cf.HighlyViewed,
  cf.ChildAnswers
FROM complex_filters cf
ORDER BY cf.LastActivityDate DESC, cf.Score DESC
LIMIT 100;