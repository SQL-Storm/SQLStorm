-- {"query": "59079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 887} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT bh.Id) as HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    MAX(CASE WHEN bh.PostHistoryTypeId = 10 THEN bh.Comment END) as CloseReason,
    MAX(CASE WHEN bh.PostHistoryTypeId = 12 THEN bh.Text END) as DeleteReason,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as WikiCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 4 THEN p.Id END) as TagWikiExcerptCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 5 THEN p.Id END) as TagWikiCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 6 THEN p.Id END) as ModeratorNominationCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 7 THEN p.Id END) as WikiPlaceholderCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 8 THEN p.Id END) as PrivilegeWikiCount,
    AVG(p.Score) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as AvgScore30Days,
    ROW_NUMBER() over (partition by u.Id order by p.CreationDate) as PostRank,
    DENSE_RANK() over (order by p.Score desc) as ScoreRank,
    NTILE(100) over (order by p.Score) as ScorePercentile,
    LAG(p.Score, 1) over (partition by u.Id order by p.CreationDate) as PrevScore,
    LEAD(p.Score, 1) over (partition by u.Id order by p.CreationDate) as NextScore,
    p.Score - LAG(p.Score, 1) over (partition by u.Id order by p.CreationDate) as ScoreDiff,
    CASE WHEN p.Score > (SELECT AVG(Score) FROM Posts) THEN 1 ELSE 0 END as AboveAvg,
    CASE WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 1 ELSE 0 END as AboveAvgQuestion,
    CASE WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 1 ELSE 0 END as AboveAvgAnswer
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN (
    SELECT PostId, TagName 
    FROM Posts p2 
    JOIN unnest(string_to_array(SUBSTRING(p2.Tags, 2, LENGTH(p2.Tags)-2), '><')) AS tag ON TRUE
    JOIN Tags t ON t.TagName = tag
) t ON p.Id = t.PostId
WHERE p.CreationDate >= '2022-01-01 00:00:00'
    AND p.CreationDate < '2023-01-01 00:00:00'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT c.Id) > 10
    AND COUNT(DISTINCT v.Id) > 5
    AND COUNT(DISTINCT bh.Id) > 2
    AND COUNT(DISTINCT t.TagName) > 1
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
LIMIT 1000;