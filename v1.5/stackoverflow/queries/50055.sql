-- {"query": "50055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1005} 
WITH AnswerStats AS (
    SELECT
        p_ans.OwnerUserId,
        COUNT(p_ans.Id) AS TotalAnswers,
        SUM(p_ans.Score) AS SumAnswerScores,
        AVG(p_ans.Score) AS AvgAnswerScore,
        SUM(p_que.ViewCount) AS SumQuestionViews,
        SUM(p_que.FavoriteCount) AS SumQuestionFavorites
    FROM Posts AS p_ans
    INNER JOIN Posts AS p_que ON p_ans.ParentId = p_que.Id
    WHERE p_ans.PostTypeId = 2 -- Answers
        AND p_ans.OwnerUserId IS NOT NULL
        AND p_ans.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '3 year')
        AND (
            p_que.Tags LIKE '%<sql>%' OR
            p_que.Tags LIKE '%<python>%' OR
            p_que.Tags LIKE '%<javascript>%' OR
            p_que.Tags LIKE '%<java>%'
        )
    GROUP BY p_ans.OwnerUserId
    HAVING COUNT(p_ans.Id) > 15
),
UserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS UpVotesCast,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges
    FROM Users AS u
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId AND v.VoteTypeId = 2 -- UpMod
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE u.Reputation > 20000 AND u.LastAccessDate > (cast('2024-10-01' as date) - INTERVAL '1 year')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
CombinedUserScore AS (
    SELECT
        um.UserId,
        um.DisplayName,
        um.Reputation,
        ast.TotalAnswers,
        ast.AvgAnswerScore,
        um.CommentCount,
        um.UpVotesCast,
        um.GoldBadges,
        um.SilverBadges,
        ast.SumQuestionViews,
        (
            (ast.AvgAnswerScore * LOG(GREATEST(ast.SumQuestionViews, 1))) +
            (um.Reputation / 1000.0) +
            (um.GoldBadges * 100) +
            (um.SilverBadges * 25) +
            (um.CommentCount / 50.0)
        ) / (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - um.CreationDate)) / 31536000.0) AS WeightedScore
    FROM UserMetrics AS um
    INNER JOIN AnswerStats AS ast ON um.UserId = ast.OwnerUserId
    WHERE ast.AvgAnswerScore > 2.0
)
SELECT
    cs.DisplayName,
    cs.Reputation,
    cs.TotalAnswers,
    CAST(cs.AvgAnswerScore AS DECIMAL(10, 2)) AS AvgAnswerScore,
    cs.CommentCount,
    cs.GoldBadges,
    CAST(cs.WeightedScore AS DECIMAL(18, 4)) AS FinalScore,
    ph_edit.EditCount,
    DENSE_RANK() OVER (ORDER BY cs.WeightedScore DESC) AS UserRank
FROM CombinedUserScore AS cs
LEFT JOIN (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS EditCount
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    GROUP BY ph.UserId
) AS ph_edit ON cs.UserId = ph_edit.UserId
WHERE ph_edit.EditCount > (SELECT AVG(EditCount) FROM (SELECT COUNT(Id) AS EditCount FROM PostHistory WHERE PostHistoryTypeId IN (4, 5, 6) GROUP BY UserId) AS AvgEdits)
ORDER BY UserRank, cs.Reputation DESC
LIMIT 200;