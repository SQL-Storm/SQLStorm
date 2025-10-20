-- {"query": "397.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 19129} 
WITH
  VotesAgg AS (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ),
  CommentCounts AS (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ),
  SetA AS (
    SELECT p.Id AS PostId,
           p.Title,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.OwnerUserId,
           COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
           u.Reputation AS OwnerReputation,
           COALESCE(V.UpVotes, 0) AS UpVotes,
           COALESCE(V.DownVotes, 0) AS DownVotes,
           COALESCE(CC.CommentCount, 0) AS CommentCount,
           ( SELECT c.Text
             FROM Comments c
             WHERE c.PostId = p.Id
             ORDER BY c.CreationDate DESC
             LIMIT 1
           ) AS LastCommentSnippet,
           (COALESCE(u.DisplayName, p.OwnerDisplayName) || ' [' || COALESCE(u.Reputation::text, '0') || ']') AS OwnerSummary
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN VotesAgg V ON V.PostId = p.Id
    LEFT JOIN CommentCounts CC ON CC.PostId = p.Id
    WHERE p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
      AND COALESCE(V.UpVotes, 0) > 50
  ),
  SetB AS (
    SELECT p.Id AS PostId,
           p.Title,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.OwnerUserId,
           COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
           u.Reputation AS OwnerReputation,
           COALESCE(V.UpVotes, 0) AS UpVotes,
           COALESCE(V.DownVotes, 0) AS DownVotes,
           COALESCE(CC.CommentCount, 0) AS CommentCount,
           ( SELECT c.Text
             FROM Comments c
             WHERE c.PostId = p.Id
             ORDER BY c.CreationDate DESC
             LIMIT 1
           ) AS LastCommentSnippet,
           (COALESCE(u.DisplayName, p.OwnerDisplayName) || ' [' || COALESCE(u.Reputation::text, '0') || ']') AS OwnerSummary
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN VotesAgg V ON V.PostId = p.Id
    LEFT JOIN CommentCounts CC ON CC.PostId = p.Id
    WHERE p.ViewCount > 5000
      AND COALESCE(V.UpVotes, 0) > 5
  ),
  AllPosts AS (
    SELECT * FROM SetA
    UNION ALL
    SELECT * FROM SetB
  ),
  Ranked AS (
    SELECT a.*,
           ROW_NUMBER() OVER (ORDER BY UpVotes DESC, ViewCount DESC, Score DESC) AS GlobalRank
    FROM AllPosts a
  )
SELECT PostId, Title, CreationDate, Score, ViewCount, OwnerUserId, OwnerName, OwnerReputation,
       UpVotes, DownVotes, CommentCount, LastCommentSnippet, OwnerSummary, GlobalRank
FROM Ranked
ORDER BY GlobalRank
LIMIT 200;