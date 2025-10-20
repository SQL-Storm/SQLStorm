-- {"query": "379.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 26279} 
WITH
  Q AS (
    SELECT p.Id AS PostId, p.Title, p.OwnerUserId, p.ViewCount, p.Score, p.CreationDate, p.LastActivityDate,
           p.AnswerCount, p.CommentCount, p.Tags, p.PostTypeId
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  TagListCTE AS (
    SELECT q.PostId, STRING_AGG(DISTINCT TRIM(t.TagName), ',') AS TagList
    FROM Q q
    LEFT JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS t(TagName) ON true
    GROUP BY q.PostId
  ),
  UpVotes AS (
    SELECT p.Id AS PostId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
  ),
  DownVotes AS (
    SELECT p.Id AS PostId, SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
  ),
  CommentCounts AS (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ),
  Eng AS (
    SELECT q.PostId, q.Title, q.OwnerUserId, q.ViewCount, q.Score, q.CreationDate, q.LastActivityDate, q.AnswerCount,
           COALESCE(uv.UpVotes, 0) AS UpVotes,
           COALESCE(dv.DownVotes, 0) AS DownVotes,
           COALESCE(cc.CommentCount, 0) AS CommentCount
    FROM Q q
    LEFT JOIN UpVotes uv ON q.PostId = uv.PostId
    LEFT JOIN DownVotes dv ON q.PostId = dv.PostId
    LEFT JOIN CommentCounts cc ON q.PostId = cc.PostId
  ),
  Eng2 AS (
    SELECT e.PostId, e.Title, e.OwnerUserId, e.ViewCount, e.Score, e.CreationDate, e.LastActivityDate, e.AnswerCount,
           e.UpVotes, e.DownVotes, e.CommentCount,
           CASE
             WHEN e.ViewCount > 0 THEN LOG(1.0 + e.ViewCount) * (1.0 + e.UpVotes) / NULLIF(1.0 + e.CommentCount, 0)
             ELSE 0
           END AS EngagementScore
    FROM Eng e
  ),
  Ranked AS (
    SELECT e2.*,
           ROW_NUMBER() OVER (ORDER BY e2.EngagementScore DESC NULLS LAST) AS rn
    FROM Eng2 e2
  ),
  Top100 AS (
    SELECT *
    FROM Ranked
    WHERE rn <= 100
  ),
  TagListFinal AS (
    SELECT t.PostId, COALESCE(tl.TagList, '') AS TagList
    FROM Top100 t
    LEFT JOIN TagListCTE tl ON t.PostId = tl.PostId
  ),
  BadgesCount AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId
  ),
  FinalA AS (
    SELECT t.PostId, t.Title, t.OwnerUserId, u.DisplayName AS OwnerDisplayName, t.ViewCount, t.Score, t.CreationDate, t.LastActivityDate,
           t.AnswerCount, t.CommentCount, t.EngagementScore AS Metric, TAG.TagList, COALESCE(b.BadgeCount, 0) AS BadgeCount
    FROM Top100 t
    LEFT JOIN Users u ON t.OwnerUserId = u.Id
    LEFT JOIN TagListFinal TAG ON t.PostId = TAG.PostId
    LEFT JOIN BadgesCount b ON t.OwnerUserId = b.UserId
  ),
  Responses AS (
    SELECT a.Id AS PostId, a.Title, a.OwnerUserId, a.ViewCount, a.Score, a.CreationDate, a.LastActivityDate,
           a.AnswerCount, a.CommentCount
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= (CURRENT_DATE - INTERVAL '3 years')
  ),
  AnswersWithBounty AS (
    SELECT resp.PostId, resp.Title, resp.OwnerUserId, u.DisplayName AS OwnerDisplayName, resp.ViewCount, resp.Score, resp.CreationDate, resp.LastActivityDate,
           resp.AnswerCount, resp.CommentCount,
           AVG(v.BountyAmount) AS AvgBounty
    FROM Responses resp
    LEFT JOIN Votes v ON resp.PostId = v.PostId
    LEFT JOIN Users u ON resp.OwnerUserId = u.Id
    GROUP BY resp.PostId, resp.Title, resp.OwnerUserId, u.DisplayName, resp.ViewCount, resp.Score, resp.CreationDate, resp.LastActivityDate, resp.AnswerCount, resp.CommentCount
  ),
  TopAnswers AS (
    SELECT * FROM AnswersWithBounty
    ORDER BY AvgBounty DESC NULLS LAST
    LIMIT 50
  ),
  FinalB AS (
    SELECT ta.PostId, ta.Title, ta.OwnerUserId, ta.OwnerDisplayName, ta.ViewCount, ta.Score, ta.CreationDate, ta.LastActivityDate,
           ta.AnswerCount, ta.CommentCount, ta.AvgBounty AS Metric, '' AS TagList,
           COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = ta.OwnerUserId), 0) AS BadgeCount
    FROM TopAnswers ta
  )

SELECT *
FROM FinalA
UNION ALL
SELECT *
FROM FinalB
ORDER BY Metric DESC NULLS LAST
LIMIT 200;