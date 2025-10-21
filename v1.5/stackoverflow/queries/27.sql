-- {"query": "27.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 171} 
WITH RankUsers AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rn
    FROM Users
    WHERE DisplayName IS NOT NULL
), RankPosts AS (
    SELECT P.Id, P.Score, R.rn
    FROM Posts P
    JOIN RankUsers R ON P.OwnerUserId = R.Id
), AggregatedData AS (
    SELECT rp.Id, rp.Score, rp.rn, COUNT(v.Id) AS VoteCount
    FROM RankPosts rp
    LEFT JOIN Votes v ON rp.Id = v.PostId
    WHERE rp.Score > 0
    GROUP BY rp.Id, rp.Score, rp.rn
)
SELECT ap.Id, ap.Score, ap.rn, ap.VoteCount
FROM AggregatedData ap
ORDER BY ap.VoteCount DESC, ap.Score DESC;