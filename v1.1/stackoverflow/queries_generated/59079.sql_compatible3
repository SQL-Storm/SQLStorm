SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT bh.Id) AS HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    MAX(CASE WHEN bh.PostHistoryTypeId = 10 THEN bh.Comment END) AS CloseReason,
    MAX(CASE WHEN bh.PostHistoryTypeId = 12 THEN bh.Text END) AS DeleteReason,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS WikiCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 4 THEN p.Id END) AS TagWikiExcerptCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 5 THEN p.Id END) AS TagWikiCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 6 THEN p.Id END) AS ModeratorNominationCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 7 THEN p.Id END) AS WikiPlaceholderCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 8 THEN p.Id END) AS PrivilegeWikiCount,
    AVG(p.Score) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS AvgScore30Days,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS PostRank,
    DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
    NTILE(100) OVER (ORDER BY p.Score) AS ScorePercentile,
    LAG(p.Score, 1) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS PrevScore,
    LEAD(p.Score, 1) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS NextScore,
    p.Score - LAG(p.Score, 1) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS ScoreDiff,
    CASE WHEN p.Score > (SELECT AVG(p2.Score) FROM Posts p2) THEN 1 ELSE 0 END AS AboveAvg,
    CASE WHEN p.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 1) THEN 1 ELSE 0 END AS AboveAvgQuestion,
    CASE WHEN p.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 2) THEN 1 ELSE 0 END AS AboveAvgAnswer
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN (
    SELECT p2.Id AS PostId, tagval AS TagName
    FROM Posts p2,
    LATERAL (
        SELECT TRIM(BOTH '<>' FROM regexp_substr(p2.Tags, '[^><]+', 1, seq)) AS tagval
        FROM (
            WITH RECURSIVE nums(n) AS (
                SELECT 1
                UNION ALL
                SELECT n+1 FROM nums WHERE n < 100
            )
            SELECT n AS seq FROM nums
        ) seqs
        WHERE regexp_substr(p2.Tags, '[^><]+', 1, seqs.seq) IS NOT NULL
    ) tags
) t ON p.Id = t.PostId
WHERE p.CreationDate >= CAST('2022-01-01 00:00:00' AS TIMESTAMP)
  AND p.CreationDate < CAST('2023-01-01 00:00:00' AS TIMESTAMP)
  AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate,
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT c.Id) > 10
    AND COUNT(DISTINCT v.Id) > 5
    AND COUNT(DISTINCT bh.Id) > 2
    AND COUNT(DISTINCT t.TagName) > 1
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
FETCH FIRST 1000 ROWS ONLY;