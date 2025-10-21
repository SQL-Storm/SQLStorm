-- {"query": "45078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 319}
WITH HighRepUserPosts AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.Score, 
        u.Reputation,
        NTILE(10) OVER (ORDER BY p.Score DESC) AS ScoreTier
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 10000 
    AND p.PostTypeId IN (1,2)
),
PostInteractions AS (
    SELECT 
        hup.ScoreTier,
        AVG(v.VoteTypeId) AS AvgVoteType,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(p.AnswerCount) AS MaxAnswers
    FROM HighRepUserPosts hup
    LEFT JOIN Votes v ON v.PostId = hup.Id
    LEFT JOIN Comments c ON c.PostId = hup.Id
    LEFT JOIN Posts p ON p.Id = hup.Id
    GROUP BY hup.ScoreTier
)
SELECT 
    ScoreTier,
    ROUND(AvgVoteType, 2) AS NormalizedVoteAverage,
    CommentCount,
    MaxAnswers
FROM PostInteractions
ORDER BY ScoreTier;
