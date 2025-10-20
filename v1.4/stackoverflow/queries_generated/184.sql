-- {"query": "184.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1671} 
WITH latest_edit AS (
  SELECT p.Id AS PostId,
         MAX(ph.CreationDate) AS LastEditDate
  FROM Posts p
  LEFT JOIN PostHistory ph
         ON ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (10,11,12,13,14,15,16,17,18,19,24,33,34,37,38,50,52,53,66)
  GROUP BY p.Id
),
vote_agg AS (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount,
         MAX(BountyAmount) AS MaxBounty
  FROM Votes
  GROUP BY PostId
),
posts_enhanced AS (
  SELECT p.Id,
         p.OwnerUserId,
         p.Title,
         p.Tags,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         p.PostTypeId,
         COALESCE(v.vote_UpModCount, 0) AS UpVotes,
         COALESCE(v.vote_DownModCount, 0) AS DownVotes,
         COALESCE(le.LastEditDate, p.CreationDate) AS LastActivityDate
  FROM Posts p
  LEFT JOIN (
      SELECT PostId,
             SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS vote_UpModCount,
             SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS vote_DownModCount
      FROM Votes
      GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN latest_edit le ON le.PostId = p.Id
)
SELECT pe.Id AS PostId,
       pe.Title,
       pe.Tags,
       pe.Score,
       pe.ViewCount,
       pe.CreationDate,
       pe.PostTypeId,
       pe.UpVotes,
       pe.DownVotes,
       pe.LastActivityDate,
       u.DisplayName AS OwnerDisplayName,
       u.Reputation,
       COALESCE(cm.CommentCount, 0) AS CommentCount,
       COALESCE(vm.MaxBounty, 0) AS MaxBounty
FROM posts_enhanced pe
JOIN Users u ON u.Id = pe.OwnerUserId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
) cm ON cm.PostId = pe.Id
LEFT JOIN vote_agg vm ON vm.PostId = pe.Id
WHERE pe.PostTypeId = 1
ORDER BY pe.Score DESC, pe.ViewCount DESC
LIMIT 100;