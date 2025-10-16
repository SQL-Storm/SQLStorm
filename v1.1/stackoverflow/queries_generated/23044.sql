-- {"query": "23044.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 920} 

WITH TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.FavoriteCount,
        p.Score AS QuestionScore,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY p.FavoriteCount DESC) AS RankInLocation,
        STRING_AGG(t.TagName, ', ') AS TagList
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.FavoriteCount > 10
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.FavoriteCount, p.Score, p.CreationDate, u.Location
    HAVING COUNT(DISTINCT t.TagName) >= 2
),
AnswerStats AS (
    SELECT 
        pa.ParentId AS QuestionId,
        COUNT(pa.Id) AS AnswerCount,
        MAX(pa.Score) AS MaxAnswerScore,
        AVG(CASE WHEN pa.Score IS NULL THEN 0 ELSE pa.Score END) AS AvgAnswerScore
    FROM Posts pa
    WHERE pa.PostTypeId = 2
    GROUP BY pa.ParentId
),
RecentEdits AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9) AND ph.Comment IS NOT NULL
    GROUP BY ph.PostId
)
SELECT 
    tq.QuestionId,
    tq.Title,
    u.DisplayName AS OwnerName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    tq.FavoriteCount,
    tq.QuestionScore,
    COALESCE(as1.AnswerCount, 0) AS AnswerCount,
    COALESCE(as1.MaxAnswerScore, 0) AS MaxAnswerScore,
    as1.AvgAnswerScore,
    tq.TagList,
    tq.RankInLocation,
    re.LastEditDate,
    re.EditCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.QuestionId AND c.Score > 5) AS HighScoreComments,
    CASE 
        WHEN tq.FavoriteCount > 100 THEN 'Highly Favorited'
        WHEN tq.FavoriteCount BETWEEN 50 AND 100 THEN 'Popular'
        ELSE 'Interesting'
    END AS PopularityCategory,
    EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = tq.QuestionId AND v.VoteTypeId = 5) AS HasFavorites
FROM TopQuestions tq
LEFT JOIN AnswerStats as1 ON tq.QuestionId = as1.QuestionId
LEFT JOIN RecentEdits re ON tq.QuestionId = re.PostId
INNER JOIN Users u ON tq.OwnerUserId = u.Id
WHERE tq.RankInLocation <= 5
UNION ALL
SELECT 
    p.Id AS QuestionId,
    p.Title,
    NULL AS OwnerName,
    NULL AS OwnerReputation,
    p.FavoriteCount,
    p.Score AS QuestionScore,
    COALESCE((SELECT COUNT(*) FROM Posts pa WHERE pa.ParentId = p.Id AND pa.PostTypeId = 2), 0) AS AnswerCount,
    COALESCE((SELECT MAX(pa.Score) FROM Posts pa WHERE pa.ParentId = p.Id AND pa.PostTypeId = 2), 0) AS MaxAnswerScore,
    COALESCE((SELECT AVG(CASE WHEN pa.Score IS NULL THEN 0 ELSE pa.Score END) FROM Posts pa WHERE pa.ParentId = p.Id AND pa.PostTypeId = 2), 0) AS AvgAnswerScore,
    (SELECT STRING_AGG(TagName, ', ') FROM Tags WHERE p.Tags LIKE '%' || TagName || '%') AS TagList,
    NULL AS RankInLocation,
    NULL AS LastEditDate,
    NULL AS EditCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5) AS HighScoreComments,
    'Archived' AS PopularityCategory,
    FALSE AS HasFavorites
FROM Posts p
WHERE p.PostTypeId = 1 AND p.FavoriteCount IS NULL AND p.ClosedDate IS NOT NULL
ORDER BY FavoriteCount DESC NULLS LAST, QuestionScore DESC;
