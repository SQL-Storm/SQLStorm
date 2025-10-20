WITH RecursiveCommentKarma AS (
    SELECT 
        c.UserId,
        u.DisplayName,
        (AVG(NULLIF(c.Score, 0)) OVER (PARTITION BY c.UserId ORDER BY c.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) *
            LN(COALESCE(COUNT(*) FILTER (WHERE c.Score > 0) OVER (PARTITION BY c.UserId), 1) + 1) AS AvgTrendScore,
        MAX(c.CreationDate) AS LastCommentDt
    FROM Comments c
    JOIN Users u ON c.UserId = u.Id
    GROUP BY c.UserId, u.DisplayName, c.CreationDate, c.Score
)
SELECT
    UserId,
    DisplayName,
    AvgTrendScore,
    LastCommentDt
FROM RecursiveCommentKarma;