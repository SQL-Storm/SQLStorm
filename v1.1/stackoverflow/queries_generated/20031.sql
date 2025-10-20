-- {"query": "20031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1531} 

WITH UserQuestionStats AS (
    -- CTE 1: Gathers detailed statistics for each question, including time-to-answer and rank within user's posts.
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.FavoriteCount,
        -- Use a correlated subquery to find the creation date of the accepted answer.
        (SELECT ans.CreationDate FROM Posts ans WHERE ans.Id = p.AcceptedAnswerId) AS AcceptedAnswerDate,
        -- Calculate the time difference between the question and its accepted answer.
        (SELECT ans.CreationDate FROM Posts ans WHERE ans.Id = p.AcceptedAnswerId) - p.CreationDate AS TimeToAcceptedAnswer,
        -- Rank questions for each user based on a composite score of Score and ViewCount.
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Questions
        AND p.OwnerUserId IS NOT NULL
        AND p.ClosedDate IS NULL
),
UserEngagementProfile AS (
    -- CTE 2: Aggregates user-level metrics like reputation, badge counts, and overall activity.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS JoinDate,
        u.Location,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgPostScore,
        -- Use subqueries to get badge counts, which can be expensive but good for benchmarks.
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        -- Find the time elapsed between a user's first and last comment.
        MAX(c.CreationDate) - MIN(c.CreationDate) AS CommentingLifespan
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    WHERE
        u.Reputation > 5000 AND u.AboutMe IS NOT NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)
),
CommunityContributors AS (
    -- CTE 3: Identifies users who contribute through edits, using PostHistory.
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS EditedPostsCount
    FROM
        PostHistory ph
    WHERE
        ph.UserId IS NOT NULL
        AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY
        ph.UserId
)
-- Main Query: Combine data from CTEs to create a comprehensive report on active, high-quality users.
-- Part 1: "Established Experts"
SELECT
    uep.DisplayName,
    uep.Reputation,
    uep.TotalAnswers,
    uep.GoldBadges,
    CONCAT('Location: ', COALESCE(uep.Location, 'Unknown')) AS UserLocation,
    -- Complex CASE statement to categorize users.
    CASE
        WHEN uep.Reputation > 100000 THEN 'Elite Contributor'
        WHEN uep.Reputation > 50000 THEN 'Senior Contributor'
        ELSE 'Regular Contributor'
    END AS ContributorLevel,
    uqs.Score AS TopQuestionScore,
    uqs.ViewCount AS TopQuestionViews,
    EXTRACT(EPOCH FROM uqs.TimeToAcceptedAnswer) / 3600 AS HoursToAcceptedAnswer,
    -- Use a window function on the final joined result.
    NTILE(100) OVER (ORDER BY uep.AvgPostScore DESC, uep.Reputation DESC) AS EngagementPercentile,
    cc.EditedPostsCount,
    'Expert' AS ProfileType
FROM
    UserEngagementProfile uep
JOIN
    UserQuestionStats uqs ON uep.UserId = uqs.OwnerUserId AND uqs.QuestionRank <= 3 -- Consider top 3 questions
LEFT JOIN
    CommunityContributors cc ON uep.UserId = cc.UserId
WHERE
    uep.GoldBadges > 1
    AND uqs.TimeToAcceptedAnswer IS NOT NULL
    AND uqs.TimeToAcceptedAnswer < INTERVAL '7 day'
    AND LENGTH(uqs.Tags) - LENGTH(REPLACE(uqs.Tags, '><', '')) > 2 -- At least 3 tags on their top posts

UNION ALL

-- Part 2: "Rising Stars" - Users who are newer but have highly voted content.
SELECT
    u.DisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM Posts p_ans WHERE p_ans.OwnerUserId = u.Id AND p_ans.PostTypeId = 2),
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1),
    'N/A',
    'Rising Star',
    p.Score,
    p.ViewCount,
    NULL,
    NTILE(100) OVER (ORDER BY p.Score DESC, u.Reputation DESC),
    NULL,
    'RisingStar' AS ProfileType
FROM
    Users u
JOIN
    Posts p ON u.Id = p.OwnerUserId
WHERE
    u.CreationDate > (CURRENT_DATE - INTERVAL '3 year')
    AND u.Reputation BETWEEN 1000 AND 5000
    AND p.PostTypeId = 2 -- Focus on a single great answer
    AND p.Score > (SELECT AVG(Score) * 5 FROM Posts WHERE PostTypeId = 2) -- Answer score is 5x the average
    AND p.Id NOT IN (SELECT PostId FROM Votes WHERE VoteTypeId = 12) -- Exclude posts ever flagged as spam
ORDER BY
    Reputation DESC, TopQuestionScore DESC NULLS LAST
LIMIT 250;
