-- {"query": "44010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 593}
Here is an elaborate SQL query for performance benchmarking on the StackOverflow database schema:

```sql
WITH recent_posts AS (
  SELECT p.Id, p.CreationDate, p.OwnerUserId, p.ParentId, p.PostTypeId, p.Tags, p.Title, p.ClosedDate, p.CommunityOwnedDate
  FROM Posts p
  WHERE p.CreationDate >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR)
)
SELECT
  u.DisplayName AS OwnerDisplayName,
  t.TagName,
  COUNT(rp.Id) AS PostCount,
  AVG(DATEDIFF(COALESCE(rp.ClosedDate, rp.CommunityOwnedDate, CURRENT_TIMESTAMP), rp.CreationDate)) AS AvgDaysTillClosed,
  ROUND(SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(rp.Id), 2) AS QuestionPct,
  ROUND(SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) * 1.0 / COUNT(rp.Id), 2) AS AnswerPct,
  ROUND(SUM(CASE WHEN rp.ParentId IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(rp.Id), 2) AS ChildPostPct
FROM recent_posts rp
JOIN Users u ON rp.OwnerUserId = u.Id
JOIN Tags t ON FIND_IN_SET(t.TagName, rp.Tags) > 0
GROUP BY u.DisplayName, t.TagName
ORDER BY PostCount DESC
LIMIT 100;
```

This query first creates a common table expression (CTE) called `recent_posts` that selects only posts created within the last year. It then aggregates various statistics about these recent posts, grouped by the post owner's display name and the post's tags. The resulting metrics include:

- Total post count
- Average days until a post is closed or community owned
- Percentage of questions, answers, and child posts
- Top 100 most active post owners and tags

The query is designed to be computationally intensive and cover a wide range of data, making it suitable for performance benchmarking purposes.
