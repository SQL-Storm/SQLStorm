-- {"query": "20054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1472} 

WITH UserActivity AS (
    -- Step 1: Aggregate user-level statistics like badge counts, edit counts, and comment scores.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p_edit WHERE p_edit.LastEditorUserId = u.Id) AS TotalEdits,
        (SELECT COALESCE(SUM(c.Score), 0) FROM Comments c WHERE c.UserId = u.Id) AS TotalCommentScore
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 1500 AND u.AboutMe IS NOT NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RankedContent AS (
    -- Step 2: For each user, rank their answers and calculate time gaps between posts.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.PostTypeId,
        p.CreationDate,
        p.Tags,
        p.Title,
        p.ViewCount,
        -- Use a window function to rank answers by score for each user.
        CASE
            WHEN p.PostTypeId = 2 THEN ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC)
            ELSE NULL
        END AS AnswerRank,
        -- Use LAG to find the time difference in hours between a user's consecutive posts.
        EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))) / 3600.0 AS HoursSinceLastPost
    FROM
        Posts p
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.CommunityOwnedDate IS NULL
),
UserContributionProfile AS (
    -- Step 3: Combine user stats with their top-ranked answer and average question performance.
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.UserCreationDate,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.TotalEdits,
        ua.TotalCommentScore,
        -- Aggregate stats for user's questions
        AVG(CASE WHEN rc.PostTypeId = 1 THEN rc.Score END) AS AvgQuestionScore,
        SUM(CASE WHEN rc.PostTypeId = 1 THEN rc.ViewCount END) AS TotalQuestionViews,
        -- Get details of the user's best answer
        MAX(CASE WHEN rc.AnswerRank = 1 THEN rc.Score END) AS BestAnswerScore,
        MAX(CASE WHEN rc.AnswerRank = 1 THEN rc.Title END) AS BestAnswerQuestionTitle,
        MAX(CASE WHEN rc.AnswerRank = 1 THEN rc.HoursSinceLastPost END) AS BestAnswerHoursSinceLastPost
    FROM
        UserActivity ua
    JOIN
        RankedContent rc ON ua.UserId = rc.OwnerUserId
    GROUP BY
        ua.UserId, ua.DisplayName, ua.Reputation, ua.UserCreationDate, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges, ua.TotalEdits, ua.TotalCommentScore
    HAVING
        -- Filter for users who have at least one answer.
        MAX(CASE WHEN rc.PostTypeId = 2 THEN 1 ELSE 0 END) = 1
)
-- Final SELECT: Identify top users based on a complex scoring model and join with other tables to fetch more details.
SELECT
    ucp.DisplayName,
    ucp.Reputation,
    -- A complex, weighted score to rank users.
    (ucp.Reputation * 0.4 + ucp.TotalQuestionViews * 0.1 + ucp.BestAnswerScore * 150 + ucp.GoldBadges * 500 + ucp.TotalCommentScore * 5) / (EXTRACT(EPOCH FROM (NOW() - ucp.UserCreationDate))/(86400.0*365) + 1) AS OverallPerformanceScore,
    ucp.BestAnswerQuestionTitle,
    ucp.BestAnswerScore,
    -- Correlated subquery: Find the number of 'Duplicate' PostLinks pointing to any of the user's questions.
    (SELECT COUNT(*)
     FROM PostLinks pl
     JOIN Posts p_sub ON pl.RelatedPostId = p_sub.Id
     WHERE p_sub.OwnerUserId = ucp.UserId AND pl.LinkTypeId = 3) AS DuplicateQuestionCount,
    LastVote.LastVoteDate
FROM
    UserContributionProfile ucp
-- Use an outer join with a subquery that finds the last 'UpMod' vote cast by the user.
LEFT JOIN LATERAL (
    SELECT
        v.CreationDate AS LastVoteDate
    FROM Votes v
    WHERE v.UserId = ucp.UserId AND v.VoteTypeId = 2 -- UpMod
    ORDER BY v.CreationDate DESC
    LIMIT 1
) AS LastVote ON TRUE
WHERE
    -- Complicated predicate logic
    ucp.GoldBadges > 0
    AND ucp.BestAnswerScore > ucp.AvgQuestionScore
    AND ucp.TotalEdits > (ucp.GoldBadges + ucp.SilverBadges + ucp.BronzeBadges)
    -- Use an EXISTS subquery to check if the user has answered a question with a specific tag that has a high favorite count.
    AND EXISTS (
        SELECT 1
        FROM Posts q
        JOIN Posts a ON q.Id = a.ParentId
        WHERE a.OwnerUserId = ucp.UserId
          AND q.Tags LIKE '%<database>%'
          AND COALESCE(q.FavoriteCount, 0) > 50
    )
ORDER BY
    OverallPerformanceScore DESC NULLS LAST,
    ucp.Reputation DESC
LIMIT 100;
