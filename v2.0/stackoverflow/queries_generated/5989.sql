-- {"query": "5989.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 939} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.EmailHash,
    u.AccountId,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Views, u.UpVotes, u.DownVotes, u.ProfileImageUrl, u.Location,
    u.EmailHash, u.AccountId
),
hot_tags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TotalTagCount,
    AVG(t.Count) AS AvgTagCount
  FROM Tags t
  GROUP BY t.TagName
  HAVING SUM(t.Count) > 100
),
top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.CreationDate > NOW() - INTERVAL '1 year'
),
complex_filter AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.Tags,
    tq.Score,
    tq.ViewCount,
    tq.CreationDate,
    tq.LastActivityDate,
    tq.OwnerUserId,
    tq.OwnerDisplayName,
    HAS_ACCESS_RIGHTS(tq.OwnerUserId) AS HasRights
  FROM top_questions tq
  WHERE (tq.Score >= 10 OR tq.ViewCount >= 500)
    OR (TO_CHAR(tq.CreationDate, 'YYYY') = TO_CHAR(NOW(), 'YYYY'))
),
-- Example of correlated subquery with window function and NULL handling
final_rows AS (
  SELECT
    cf.PostId,
    cf.Title,
    cf.Tags,
    cf.Score,
    cf.ViewCount,
    cf.CreationDate,
    cf.LastActivityDate,
    cf.OwnerUserId,
    cf.OwnerDisplayName,
    CASE
      WHEN cf.HasRights IS TRUE THEN 'Granted'
      WHEN cf.HasRights IS FALSE THEN 'Denied'
      ELSE 'Unknown'
    END AS OwnerRightsStatus,
    (SELECT COALESCE(B.MaxBounty, 0)
     FROM (
       SELECT MAX(v.BountyAmount) AS MaxBounty
       FROM Votes v
       WHERE v.PostId = cf.PostId AND v.VoteTypeId = 8
     ) B
     ) AS MaxBountyOnPost,
    1 AS IsBenchmarkRow
  FROM complex_filter cf
  ORDER BY cf.Score DESC, cf.ViewCount DESC
  OFFSET 0 ROWS FETCH FIRST 100 ROWS ONLY
)
SELECT
  fr.PostId,
  fr.Title,
  fr.Tags,
  fr.Score,
  fr.ViewCount,
  fr.CreationDate,
  fr.LastActivityDate,
  fr.OwnerUserId,
  fr.OwnerDisplayName,
  fr.OwnerRightsStatus,
  fr.MaxBountyOnPost,
  fr.IsBenchmarkRow
FROM final_rows fr
LEFT JOIN recent_user_activity rua ON rua.UserId = fr.OwnerUserId
LEFT JOIN hot_tags ht ON ht.TagName = ANY(string_to_array(substring(fr.Tags, 2, length(fr.Tags)-2), '><'))
INNER JOIN LATERAL (
  SELECT
    p.Id,
    p.Title,
    p.Body,
    p.LastEditDate
  FROM Posts p
  WHERE p.OwnerUserId = fr.OwnerUserId
  ORDER BY p.LastEditDate DESC
  LIMIT 1
) AS last_post(p)
ON TRUE
WHERE fr.ViewCount IS NOT NULL
ORDER BY fr.Score DESC, fr.ViewCount DESC, fr.CreationDate DESC;