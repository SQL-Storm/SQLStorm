WITH GoldBadgeUsers AS (
    SELECT UserId, Name AS BadgeName
    FROM Badges
    WHERE (Class = 1 AND Name LIKE '%gold%') OR (Class = 1 AND TagBased = TRUE)
),
QuestionStats AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.CreationDate,
        CASE 
            WHEN p.Tags IS NOT NULL THEN regexp_split_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><') 
            ELSE NULL 
        END AS TagArray,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3) AND v.UserId IS NOT NULL) AS VoteCount,
        (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS NetVotes
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserQuestionAggregates AS (
    SELECT 
        q.OwnerUserId,
        COUNT(q.Id) AS TotalQuestions,
        AVG(CASE WHEN q.Score > 10 THEN q.Score ELSE NULL END) AS AvgHighScore,
        SUM(q.NetVotes) AS TotalNetVotes,
        MAX(q.ViewCount) AS MaxViews
    FROM QuestionStats q
    GROUP BY q.OwnerUserId
),
RankedUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ua.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(ua.AvgHighScore, 0) AS AvgHighScore,
        COALESCE(ua.TotalNetVotes, 0) AS TotalNetVotes,
        COALESCE(ua.MaxViews, 0) AS MaxViews,
        g.BadgeName,
        ROW_NUMBER() OVER (ORDER BY (COALESCE(ua.TotalNetVotes, 0) + u.Reputation / 10.0) DESC) AS Rank
    FROM Users u
    LEFT JOIN GoldBadgeUsers g ON u.Id = g.UserId
    LEFT JOIN UserQuestionAggregates ua ON u.Id = ua.OwnerUserId
    WHERE g.BadgeName IS NOT NULL OR COALESCE(ua.TotalQuestions, 0) > 0
)
SELECT 
    ru.Rank,
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalQuestions,
    ROUND(CAST(ru.AvgHighScore AS NUMERIC), 2) AS AvgHighScore,
    ru.TotalNetVotes,
    ru.MaxViews,
    ru.BadgeName,
    CASE 
        WHEN ru.TotalQuestions > 100 AND ru.AvgHighScore > 20 THEN 'SuperUser'
        WHEN ru.TotalQuestions > 50 OR ru.Reputation > 50000 THEN 'Pro'
        ELSE 'Amateur'
    END AS UserLevel,
    (ru.TotalNetVotes - ru.TotalQuestions) AS NetVotePerQuestion,
    COALESCE(
        (SELECT STRING_AGG(tag, ', ')
         FROM (
             SELECT unnest(ARRAY['tech', 'sql', 'performance']) AS tag
         ) t
         WHERE EXISTS (
             SELECT 1 FROM QuestionStats qs 
             WHERE qs.OwnerUserId = ru.Id AND qs.NetVotes > 0
         )
         LIMIT 1
        ), 'None'
    ) AS SampleTags
FROM RankedUsers ru
WHERE ru.Rank <= 100
GROUP BY
    ru.Rank,
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalQuestions,
    ru.AvgHighScore,
    ru.TotalNetVotes,
    ru.MaxViews,
    ru.BadgeName
ORDER BY ru.Rank, ru.TotalNetVotes DESC;