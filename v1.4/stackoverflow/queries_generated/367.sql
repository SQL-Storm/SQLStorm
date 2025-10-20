-- {"query": "367.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 19423} 
WITH
  recent_posts AS (
     SELECT p.Id AS PostId, p.PostTypeId, p.Title, p.Tags, p.OwnerUserId, p.CreationDate, p.LastActivityDate,
            p.ViewCount, p.Score, p.CommentCount, p.AcceptedAnswerId, p.ParentId, p.Body
     FROM Posts p
     WHERE p.LastActivityDate > NOW() - INTERVAL '180 days'
  ),
  owners AS (
     SELECT Id, DisplayName AS OwnerName, Reputation
     FROM Users
     UNION ALL
     SELECT -1 AS Id, 'Community' AS OwnerName, 0 AS Reputation
  ),
  votes_agg AS (
     SELECT v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
     FROM Votes v
     GROUP BY v.PostId
  ),
  comments_cnt AS (
     SELECT c.PostId, COUNT(*) AS CommentCount
     FROM Comments c
     GROUP BY c.PostId
  ),
  post_tags AS (
     SELECT rp.PostId, tn.TagName
     FROM recent_posts rp
     LEFT JOIN LATERAL unnest(string_to_array(substring(rp.Tags, 2, LENGTH(rp.Tags) - 2), '><')) AS tn(TagName) ON TRUE
  ),
  all_tags AS (
     SELECT pt.PostId, STRING_AGG(DISTINCT pt.TagName, ',') AS AllTags
     FROM post_tags pt
     GROUP BY pt.PostId
  ),
  last_activity_enhanced AS (
     SELECT rp.PostId, rp.Title, rp.PostTypeId, rp.OwnerUserId, rp.CreationDate, rp.LastActivityDate, rp.ViewCount,
            rp.Score, rp.AcceptedAnswerId, o.OwnerName, o.Reputation,
            COALESCE(v.UpVotes, 0) AS UpVotes, COALESCE(v.DownVotes, 0) AS DownVotes,
            COALESCE(cm.CommentCount, 0) AS CommentCount,
            rp.Body
     FROM recent_posts rp
     LEFT JOIN owners o ON rp.OwnerUserId = o.Id
     LEFT JOIN votes_agg v ON rp.PostId = v.PostId
     LEFT JOIN comments_cnt cm ON rp.PostId = cm.PostId
  ),
  ranked AS (
     SELECT la.*, ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY Score DESC, LastActivityDate DESC) AS rn
     FROM last_activity_enhanced la
  ),
  final_tags AS (
     SELECT la.PostId, AllTags
     FROM all_tags la
  )
SELECT
  r.PostId,
  r.Title,
  r.PostTypeId,
  CASE r.PostTypeId
     WHEN 1 THEN 'Question'
     WHEN 2 THEN 'Answer'
     ELSE 'Other'
  END AS TypeLabel,
  r.OwnerName,
  r.Reputation,
  r.CreationDate,
  r.LastActivityDate,
  r.ViewCount,
  r.Score,
  r.UpVotes,
  r.DownVotes,
  r.CommentCount,
  r.AcceptedAnswerId,
  COALESCE(LEAD(r.LastActivityDate) OVER (PARTITION BY r.PostTypeId ORDER BY r.LastActivityDate DESC), NOW()) AS NextActivityDate,
  COALESCE(r.Body, '') AS Body,
  COALESCE(f.AllTags, '') AS AllTags,
  CONCAT('https://stackoverflow.com/', CASE WHEN r.PostTypeId = 1 THEN 'questions/' ELSE 'a/' END, r.PostId) AS Link,
  (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = r.PostId AND v2.BountyAmount IS NOT NULL) AS AvgBounty
FROM ranked r
LEFT JOIN final_tags f ON f.PostId = r.PostId
WHERE r.rn <= 100
ORDER BY r.LastActivityDate DESC, r.UpVotes - r.DownVotes DESC
LIMIT 100;