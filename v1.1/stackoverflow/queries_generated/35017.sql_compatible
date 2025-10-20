WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS PostsCount, COUNT(DISTINCT c.Id) AS CommentsCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    WHERE u.Reputation > 1000
      AND u.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10 AND COUNT(DISTINCT c.Id) > 20
), HotQuestions AS (
    SELECT p.Id AS PostId, p.Title, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate,
           -- Convert tags like '<tag1><tag2>' into a comma-separated string 'tag1,tag2'
           REPLACE(TRIM(BOTH ',' FROM REGEXP_REPLACE(p.Tags, '<([a-z0-9\\-]+)>', '\\1,', 'g')), ',,', ',') AS Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 5
      AND p.ViewCount > 1000
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
), RecentEdits AS (
    SELECT ph.PostId, COUNT(*) AS NumEdits, MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY ph.PostId
), AnsweredHotQuestions AS (
    SELECT hq.PostId, hq.Title, hq.Score, hq.ViewCount, hq.OwnerUserId, hq.Tags,
           a.Id AS AnswerId, a.Score AS AnswerScore, a.OwnerUserId AS AnswerUserId, a.CreationDate AS AnswerCreation
    FROM HotQuestions hq
    JOIN Posts a ON a.ParentId = hq.PostId AND a.PostTypeId = 2
    WHERE a.CreationDate >= hq.CreationDate
), TagPairs AS (
    -- Split the comma-separated Tags into one row per tag without using lateral / unnest subqueries
    -- This implementation uses a numbers table approach. Adjust the max number as needed for max tags per question.
    SELECT ahq.PostId AS AnswerPostId, TRIM(BOTH ' ' FROM NULLIF(SPLIT_PART(ahq.Tags, ',', n.n), '')) AS TagName
    FROM AnsweredHotQuestions ahq
    JOIN (
        SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    ) n ON n.n <= (CASE WHEN ahq.Tags IS NULL OR ahq.Tags = '' THEN 0 ELSE 10 END)
    WHERE NULLIF(SPLIT_PART(ahq.Tags, ',', n.n), '') IS NOT NULL
)
SELECT 
    au.Id AS UserId,
    au.DisplayName,
    au.Reputation,
    au.PostsCount,
    au.CommentsCount,
    COUNT(DISTINCT ahq.PostId) AS HotQuestionsAnswered,
    SUM(CASE WHEN ahq.AnswerScore > 10 THEN 1 ELSE 0 END) AS HighScoreAnswers,
    AVG(ahq.AnswerScore) AS AvgAnswerScore,
    MAX(re.NumEdits) AS MaxEditsOnAnswered,
    COUNT(DISTINCT b.Id) AS BadgesWonLastYear,
    ARRAY_AGG(DISTINCT t.TagName) AS TopTags
FROM ActiveUsers au
LEFT JOIN AnsweredHotQuestions ahq ON ahq.AnswerUserId = au.Id
LEFT JOIN RecentEdits re ON re.PostId = ahq.AnswerId
LEFT JOIN Badges b ON b.UserId = au.Id AND b.Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
LEFT JOIN TagPairs tp ON tp.AnswerPostId = ahq.PostId
LEFT JOIN Tags t ON t.TagName = tp.TagName
GROUP BY au.Id, au.DisplayName, au.Reputation, au.PostsCount, au.CommentsCount
ORDER BY HotQuestionsAnswered DESC, HighScoreAnswers DESC, au.Reputation DESC
LIMIT 50;