-- {"query": "20022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1465} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2 AND p.Score > 0), 0) AS AvgAnswerScore,
        SUM(p.ViewCount) AS TotalViewCount,
        SUM(p.FavoriteCount) FILTER (WHERE p.PostTypeId = 1) AS TotalFavoriteCount,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = u.Id AND b.Class = 1
        ) AS GoldBadges,
        (
            SELECT string_agg(DISTINCT T.tag, ', ')
            FROM Posts P_Tags
            CROSS JOIN LATERAL unnest(string_to_array(substring(P_Tags.Tags, 2, length(P_Tags.Tags)-2), '><')) AS T(tag)
            WHERE P_Tags.OwnerUserId = u.Id AND P_Tags.PostTypeId = 1
            GROUP BY P_Tags.OwnerUserId
            HAVING COUNT(DISTINCT T.tag) >= 5
        ) AS TopTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1500 AND u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
    HAVING COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) > 10
),
RankedActivity AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        QuestionsCount,
        AnswersCount,
        AvgAnswerScore,
        GoldBadges,
        TotalViewCount,
        TotalFavoriteCount,
        (Reputation * 0.4 + AvgAnswerScore * 10 + GoldBadges * 100 + AnswersCount * 2) AS EngagementScore,
        NTILE(100) OVER (ORDER BY (Reputation * 0.4 + AvgAnswerScore * 10 + GoldBadges * 100 + AnswersCount * 2) DESC) AS PercentileRank
    FROM UserActivitySummary
    WHERE TopTags IS NOT NULL
),
UserContributionDetails AS (
    SELECT
        ra.UserId,
        ra.DisplayName,
        ra.Reputation,
        ra.PercentileRank,
        ra.EngagementScore,
        p.Title AS PostTitle,
        p.PostTypeId,
        p.Score AS PostScore,
        p.CreationDate AS PostCreationDate,
        -- Calculate the time between user registration and their first post
        EXTRACT(EPOCH FROM (MIN(p.CreationDate) OVER (PARTITION BY ra.UserId) - ra.UserCreationDate)) / 3600 AS HoursToFirstPost,
        -- Find the user's score relative to the max score for that post type in that month
        p.Score * 100.0 / NULLIF(MAX(p.Score) OVER (PARTITION BY p.PostTypeId, date_trunc('month', p.CreationDate)), 0) AS RelativeScorePercent
    FROM RankedActivity ra
    JOIN Posts p ON ra.UserId = p.OwnerUserId
    WHERE ra.PercentileRank <= 5 -- Top 5% of users
),
CommunityInteraction AS (
    -- Users who provide accepted answers to questions from newer users
    SELECT
        p_ans.OwnerUserId,
        'AcceptedAnswerForNewbie' AS InteractionType,
        COUNT(DISTINCT p_q.OwnerUserId) AS NewUsersHelped,
        AVG(p_ans.Score) AS AvgHelperScore
    FROM Posts p_ans
    JOIN Posts p_q ON p_ans.Id = p_q.AcceptedAnswerId
    JOIN Users u_q ON p_q.OwnerUserId = u_q.Id
    WHERE p_ans.OwnerUserId IS NOT NULL
      AND p_q.OwnerUserId IS NOT NULL
      AND p_ans.OwnerUserId != p_q.OwnerUserId
      AND EXTRACT(EPOCH FROM (p_q.CreationDate - u_q.CreationDate)) / 86400 < 30 -- Question asked within 30 days of registration
    GROUP BY p_ans.OwnerUserId
    HAVING COUNT(*) > 1
)
SELECT
    ucd.DisplayName,
    ucd.Reputation,
    ucd.PercentileRank,
    CASE
        WHEN ucd.PostTypeId = 1 THEN 'Question'
        WHEN ucd.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostType,
    ucd.PostTitle,
    ucd.PostScore,
    ucd.RelativeScorePercent,
    ucd.HoursToFirstPost,
    COALESCE(ci.InteractionType, 'Standard Contributor') AS ContributorRole,
    COALESCE(ci.NewUsersHelped, 0) AS NewUsersHelpedCount
FROM UserContributionDetails ucd
LEFT OUTER JOIN CommunityInteraction ci ON ucd.UserId = ci.OwnerUserId
WHERE ucd.PostScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = ucd.PostTypeId)
   OR EXISTS (
        -- Find posts that were edited by a high-rep user other than the owner
        SELECT 1
        FROM PostHistory ph
        JOIN Users editor ON ph.UserId = editor.Id
        WHERE ph.PostId = (SELECT p_sub.Id FROM Posts p_sub WHERE p_sub.OwnerUserId = ucd.UserId ORDER BY p_sub.CreationDate DESC LIMIT 1)
          AND ph.PostHistoryTypeId IN (4, 5) -- Edit Title or Body
          AND ph.UserId != ucd.UserId
          AND editor.Reputation > ucd.Reputation * 1.5
   )
ORDER BY ucd.EngagementScore DESC, ucd.PostCreationDate DESC
LIMIT 250;
