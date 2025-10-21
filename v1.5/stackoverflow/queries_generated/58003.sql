-- {"query": "58003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 2542} 

WITH user_metrics AS (
    SELECT 
        u.Id,
        u.Reputation,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Score > 0) AS QuestionCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.Score > 1) AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    WHERE u.Reputation > 10000
)
SELECT 
    *,
    (QuestionCount * 5 + CommentCount * 2 + UpVotesCount * 1 + GoldBadges * 10 + SilverBadges * 5 + BronzeBadges * 2) AS TotalContribution,
    RANK() OVER (ORDER BY (QuestionCount * 5 + CommentCount * 2 + UpVotesCount * 1 + GoldBadges * 10 + SilverBadges * 5 + BronzeBadges * 2) DESC) AS OverallRank,
    DENSE_RANK() OVER (
        PARTITION BY 
            CASE
                WHEN GoldBadges >= 10 THEN 'Elite'
                WHEN GoldBadges >= 5 THEN 'Advanced'
                ELSE 'Standard'
            END
        ORDER BY (QuestionCount * 5 + CommentCount * 2 + UpVotesCount * 1) DESC
    ) AS CategoryRank
FROM user_metrics
WHERE QuestionCount > 10 AND CommentCount > 20 AND UpVotesCount > 50
ORDER BY TotalContribution DESC
LIMIT 100;
