-- {"query": "5731.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 774} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.LastEditorDisplayName,
    p.OwnerDisplayName,
    p.ContentLicense,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Location,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    -- tag count derived for quick correlation
    (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = p.OwnerUserId AND pr.PostTypeId = 1) AS UserQuestionCount,
    -- window function: running sum of Score over a moving window of 7 days
    SUM(p.Score) OVER (
      ORDER BY p.CreationDate
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS Score7DayWindow
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
),
correlated AS (
  SELECT
    rp.*,
    -- correlated subquery: count of comments on this post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS CommentCountTotal,
    -- correlated subquery: average score of related links (if any)
    (SELECT AVG(pld.Score) FROM Votes pld WHERE pld.PostId IN (SELECT RelatedPostId FROM PostLinks pl WHERE pl.PostId = rp.Id)) AS AvgRelatedVote
  FROM ranked_posts rp
),
cte_enriched AS (
  SELECT
    c.*,
    -- compute a complex predicate: high activity indicator
    CASE
      WHEN c.ViewCount > 1000 OR c.Score > 50 THEN 1
      ELSE 0
    END AS HighActivityFlag,
    -- string expression: normalized title for benchmarking
    LOWER(REGEXP_REPLACE(c.Title, '[^a-zA-Z0-9\s]', '', 'g')) AS NormalizedTitle,
    -- NULL logic: determine if Owner is missing
    CASE WHEN c.OwnerUserId IS NULL THEN 1 ELSE 0 END AS OwnerMissing
  FROM correlated c
)
SELECT
  e.Id,
  e.Title,
  e.PostTypeId,
  e.CreationDate,
  e.OwnerUserId,
  e.ViewCount,
  e.Score,
  e.Tags,
  e.LastActivityDate,
  e.AnswerCount,
  e.CommentCount,
  e.FavoriteCount,
  e.Body,
  e.ParentId,
  e.AcceptedAnswerId,
  e.LastEditorUserId,
  e.LastEditDate,
  e.LastEditorDisplayName,
  e.OwnerDisplayName,
  e.ContentLicense,
  e.Reputation,
  e.UserCreationDate,
  e.Location,
  e.LastAccessDate,
  e.Views,
  e.UpVotes,
  e.DownVotes,
  e.ProfileImageUrl,
  e.EmailHash,
  e.AccountId,
  e.UserQuestionCount,
  e.Score7DayWindow,
  e.CommentCountTotal,
  e.AvgRelatedVote,
  e.HighActivityFlag,
  e.NormalizedTitle,
  e.OwnerMissing
FROM cte_enriched e
ORDER BY e.CreationDate DESC
LIMIT 100;