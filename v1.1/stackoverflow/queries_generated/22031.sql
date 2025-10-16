-- {"query": "22031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 970} 
WITH user_stats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 END ELSE 0 END), 0) AS NetVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score ELSE NULL END) AS AvgPostScore
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (2,3)
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)
    WHERE u.Reputation > 100 AND u.CreationDate < '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
post_analysis AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COUNT(c.Id) AS CommentCount,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS Status,
        SUBSTRING(REGEXP_REPLACE(p.Tags, '[<>]', '', 'g'), 1, 100) AS CleanTags,
        EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 1) AS HasAcceptedAnswer
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.Score > 0
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.ClosedDate, p.Tags
),
complex_metrics AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.BadgeCount,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgPostScore,
        (SELECT COUNT(*) FROM post_analysis pa WHERE pa.OwnerUserId = us.Id AND pa.ScoreRank <= 10) AS Top10Questions,
        COALESCE(SUM(pa.Score), 0) AS TotalPostScore,
        AVG(pa.ViewCount) AS AvgViewCount
    FROM user_stats us
    LEFT JOIN post_analysis pa ON pa.OwnerUserId = us.Id
    GROUP BY us.Id, us.DisplayName, us.Reputation, us.NetVotes, us.BadgeCount, us.QuestionCount, us.AnswerCount, us.AvgPostScore
),
ranked_users AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY (Reputation + NetVotes * 10 + BadgeCount * 5 + Top10Questions * 20) DESC) AS InfluenceRank
    FROM complex_metrics
),
top_intersection AS (
    SELECT * FROM ranked_users WHERE InfluenceRank <= 100
    INTERSECT
    SELECT * FROM ranked_users WHERE BadgeCount >= 5 AND AvgPostScore > 5
),
final_result AS (
    SELECT 
        ti.Id,
        ti.DisplayName,
        ti.Reputation,
        ti.NetVotes,
        ti.BadgeCount,
        ti.Top10Questions,
        ti.TotalPostScore,
        ti.AvgViewCount,
        ti.InfluenceRank,
        CASE 
            WHEN ti.NetVotes > 1000 THEN 'High Voter'
            WHEN ti.NetVotes BETWEEN 100 AND 1000 THEN 'Moderate Voter'
            ELSE 'Low Voter'
        END AS VoterCategory,
        CONCAT(LEFT(ti.DisplayName, 10), '...') AS ShortName
    FROM top_intersection ti
    WHERE ti.Reputation IS NOT NULL AND ti.Id IN (
        SELECT DISTINCT u.Id FROM Users u WHERE u.Location IS NOT NULL AND u.Location LIKE '%USA%'
    )
)
SELECT 
    Id,
    DisplayName,
    Reputation,
    NetVotes,
    BadgeCount,
    Top10Questions,
    TotalPostScore,
    AvgViewCount,
    InfluenceRank,
    VoterCategory,
    ShortName
FROM final_result
ORDER BY InfluenceRank ASC
LIMIT 20;