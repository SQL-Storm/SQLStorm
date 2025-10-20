-- {"query": "21028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1341} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS RepRank
    FROM Users u
    WHERE u.Reputation > 1000
      AND u.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.ClosedDate,
        p.Title,
        COALESCE(p.Tags, '') AS Tags,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevQuestionScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate 
                           ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgScore,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AnswerCount >= 3 THEN 'WellAnswered'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'OpenActive'
        END AS QuestionStatus
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.DeletedDate IS NULL
),
TopContributors AS (
    SELECT 
        au.UserId,
        COUNT(qs.QuestionId) AS QuestionCount,
        SUM(COALESCE(qs.AnswerCount, 0)) AS TotalAnswers,
        AVG(COALESCE(qs.RollingAvgScore, 0)) AS AvgQuestionQuality,
        MAX(qs.CreationDate) AS LatestQuestion
    FROM ActiveUsers au
    LEFT JOIN QuestionStats qs ON au.UserId = qs.OwnerUserId
    GROUP BY au.UserId
    HAVING COUNT(qs.QuestionId) >= 5
),
BadgeAchievers AS (
    SELECT 
        b.UserId,
        b.Name AS BadgeName,
        b.Date,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS RecentBadgeRank,
        STRING_AGG(DISTINCT t.TagName, ', ') OVER (PARTITION BY b.UserId 
                                                   ORDER BY b.Date 
                                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeTags
    FROM Badges b
    LEFT JOIN Posts p ON b.UserId = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE b.Date > CURRENT_DATE - INTERVAL '2 years'
      AND b.Class IN (1, 2)  -- Gold and Silver badges
),
VotePatterns AS (
    SELECT 
        v.PostId,
        v.UserId,
        v.VoteTypeId,
        v.CreationDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId 
                                                                ORDER BY v.CreationDate 
                                                                ROWS UNBOUNDED PRECEDING) AS CumulativeUpvotes,
        COUNT(*) OVER (PARTITION BY v.UserId, DATE_TRUNC('month', v.CreationDate)) AS MonthlyVotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)  -- Upvotes and Downvotes
      AND v.CreationDate > CURRENT_DATE - INTERVAL '6 months'
)
SELECT 
    tc.UserId,
    au.Reputation,
    au.RepRank,
    tc.QuestionCount,
    tc.TotalAnswers,
    tc.AvgQuestionQuality,
    DATE_PART('day', CURRENT_DATE - au.CreationDate) AS DaysActive,
    ba.BadgeName,
    ba.RecentBadgeRank,
    COALESCE(vp.CumulativeUpvotes, 0) AS TotalUpvotesGiven,
    vp.MonthlyVotes,
    -- Complex string manipulation and NULL logic
    CASE 
        WHEN tc.LatestQuestion IS NULL THEN 'Inactive'
        WHEN LENGTH(COALESCE(qs.Title, '')) > 100 THEN LEFT(qs.Title, 100) || '...'
        ELSE COALESCE(qs.Title, 'No Recent Title')
    END AS LatestTitleSnippet,
    -- Elaborate predicate with subquery
    CASE 
        WHEN tc.QuestionCount > (
            SELECT AVG(q_count) 
            FROM (
                SELECT COUNT(*) AS q_count 
                FROM QuestionStats qs2 
                GROUP BY qs2.OwnerUserId
            ) sub
        ) THEN 'AboveAverage'
        ELSE 'BelowAverage'
    END AS ActivityLevel,
    -- Correlated subquery for comment density
    (SELECT AVG(LENGTH(c.Text)) 
     FROM Comments c 
     WHERE c.PostId = qs.QuestionId 
       AND c.Score > 0 
       AND c.UserId IS NOT NULL) AS AvgCommentLength,
    -- Set operator simulation with UNION-like logic in CTE
    GREATEST(
        COALESCE(tc.AvgQuestionQuality, 0),
        COALESCE(vp.CumulativeUpvotes / NULLIF(tc.QuestionCount, 0), 0),
        0
    ) AS EngagementScore
FROM TopContributors tc
INNER JOIN ActiveUsers au ON tc.UserId = au.UserId
LEFT JOIN QuestionStats qs ON tc.UserId = qs.OwnerUserId 
                          AND qs.CreationDate = (SELECT MAX(qs2.CreationDate) 
                                                 FROM QuestionStats qs2 
                                                 WHERE qs2.OwnerUserId = tc.UserId)
LEFT JOIN BadgeAchievers ba ON tc.UserId = ba.UserId 
                           AND ba.RecentBadgeRank = 1
LEFT JOIN VotePatterns vp ON tc.UserId = vp.UserId 
                         AND vp.CreationDate >= CURRENT_DATE - INTERVAL '1 month'
WHERE au.RepRank <= 100  -- Top 100 by reputation
  AND (ba.BadgeName IS NULL OR ba.BadgeName ILIKE '%gold%' OR ba.BadgeName ILIKE '%silver%')
  AND NOT EXISTS (
      SELECT 1 FROM PostHistory ph 
      WHERE ph.PostId = qs.QuestionId 
        AND ph.PostHistoryTypeId = 10  -- Closed posts
        AND ph.CreationDate > qs.CreationDate
  )
ORDER BY tc.AvgQuestionQuality DESC NULLS LAST, au.RepRank ASC
LIMIT 50;
