-- {"query": "32055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 469} 
WITH ActiveUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(p.Id) AS TotalPosts,
        AVG(p.Score) AS AverageScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(p.Id) > 10
),
TopBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgesCount,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
    FROM Votes v
    GROUP BY v.UserId
)
SELECT 
    au.Id,
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.AverageScore,
    tb.BadgesCount,
    tb.GoldBadges,
    tb.SilverBadges,
    tb.BronzeBadges,
    uv.UpVotesGiven,
    uv.DownVotesGiven
FROM ActiveUsers au
LEFT JOIN TopBadges tb ON au.Id = tb.UserId
LEFT JOIN UserVotes uv ON au.Id = uv.UserId
ORDER BY au.Reputation DESC
LIMIT 100;