-- {"query": "52096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 1005} 
WITH TopQuestions AS (
    SELECT Id, Title, ViewCount, OwnerUserId, Tags
    FROM Posts
    WHERE PostTypeId = 1 AND ViewCount > 1000 AND CreationDate >= '2018-01-01'
    ORDER BY ViewCount DESC
    LIMIT 500
),
TagSplit AS (
    SELECT tq.Id, unnest(string_to_array(substring(tq.Tags, 2, length(tq.Tags)-2), '><')) AS TagName
    FROM TopQuestions tq
    WHERE tq.Tags IS NOT NULL
),
FilteredQuestions AS (
    SELECT tq.Id
    FROM TopQuestions tq
    JOIN TagSplit ts ON ts.Id = tq.Id
    JOIN Tags tg ON tg.TagName = ts.TagName
    WHERE tg.Count > 1000 AND tg.IsModeratorOnly = false
    GROUP BY tq.Id
    HAVING COUNT(DISTINCT tg.TagName) >= 2
),
AnswerDetails AS (
    SELECT fq.Id, a.Id AS AnswerId, a.Score, a.CreationDate, a.OwnerUserId, u.Reputation
    FROM FilteredQuestions fq
    JOIN Posts a ON a.ParentId = fq.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
),
CommentDetails AS (
    SELECT fq.Id, c.Id AS CommentId, c.Score, c.CreationDate, c.UserId, u.Reputation
    FROM FilteredQuestions fq
    JOIN Comments c ON c.PostId = fq.Id
    LEFT JOIN Users u ON u.Id = c.UserId
),
VoteDetails AS (
    SELECT fq.Id, v.Id AS VoteId, v.VoteTypeId, v.CreationDate, v.UserId
    FROM FilteredQuestions fq
    JOIN Votes v ON v.PostId = fq.Id
    WHERE v.VoteTypeId IN (2,3,5)
),
BadgeDetails AS (
    SELECT DISTINCT u.Id AS UserId
    FROM Users u
    JOIN Badges b ON b.UserId = u.Id
    WHERE b.Class <= 2 AND b.Date >= '2018-01-01'
),
QuestionStats AS (
    SELECT fq.Id,
           COUNT(ad.AnswerId) AS AnswerCount,
           AVG(ad.Score) AS AvgAnswerScore,
           SUM(CASE WHEN ad.Score > 10 THEN 1 ELSE 0 END) AS HighScoreAnswers,
           AVG(EXTRACT(EPOCH FROM (ad.CreationDate - (SELECT CreationDate FROM Posts WHERE Id = fq.Id)))) AS AvgAnswerDelaySeconds
    FROM FilteredQuestions fq
    LEFT JOIN AnswerDetails ad ON ad.Id = fq.Id
    GROUP BY fq.Id
),
CommentStats AS (
    SELECT fq.Id,
           COUNT(cd.CommentId) AS CommentCount,
           AVG(cd.Score) AS AvgCommentScore,
           COUNT(DISTINCT cd.UserId) AS UniqueCommenters
    FROM FilteredQuestions fq
    LEFT JOIN CommentDetails cd ON cd.Id = fq.Id
    GROUP BY fq.Id
),
VoteStats AS (
    SELECT fq.Id,
           COUNT(vd.VoteId) AS TotalVotes,
           COUNT(CASE WHEN vd.VoteTypeId = 2 THEN 1 END) AS UpVotes,
           COUNT(CASE WHEN vd.VoteTypeId = 3 THEN 1 END) AS DownVotes,
           COUNT(CASE WHEN vd.VoteTypeId = 5 THEN 1 END) AS Bookmarks
    FROM FilteredQuestions fq
    LEFT JOIN VoteDetails vd ON vd.Id = fq.Id
    GROUP BY fq.Id
),
UserBadgeCount AS (
    SELECT u.Id, COUNT(b.Id) AS BadgeCount
    FROM Users u
    JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
)
SELECT 
    tq.Title,
    qs.AnswerCount,
    qs.AvgAnswerScore,
    qs.HighScoreAnswers,
    qs.AvgAnswerDelaySeconds,
    cs.CommentCount,
    cs.AvgCommentScore,
    cs.UniqueCommenters,
    vs.TotalVotes,
    vs.UpVotes,
    vs.DownVotes,
    vs.Bookmarks,
    u.DisplayName,
    u.Reputation AS OwnerReputation,
    ub.BadgeCount AS OwnerBadgeCount
FROM TopQuestions tq
JOIN FilteredQuestions fq ON fq.Id = tq.Id
LEFT JOIN QuestionStats qs ON qs.Id = tq.Id
LEFT JOIN CommentStats cs ON cs.Id = tq.Id
LEFT JOIN VoteStats vs ON vs.Id = tq.Id
LEFT JOIN Users u ON u.Id = tq.OwnerUserId
LEFT JOIN UserBadgeCount ub ON ub.Id = tq.OwnerUserId
WHERE u.Id IN (SELECT UserId FROM BadgeDetails)
ORDER BY tq.ViewCount DESC, qs.AnswerCount DESC
LIMIT 100;