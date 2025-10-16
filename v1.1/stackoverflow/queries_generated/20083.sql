-- {"query": "20083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1735} 

WITH UserActivity AS (
    -- Step 1: Aggregate basic user statistics and calculate a base activity score.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswerScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViewCount,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        (
            SELECT MIN(ph.CreationDate)
            FROM PostHistory ph
            WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 16 -- Community Owned
        ) AS FirstCommunityOwnedPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > '2018-01-01' AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostDetails AS (
    -- Step 2: Analyze individual posts for quality metrics, including answer times and tag complexity.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.Tags,
        p.CreationDate,
        p.FavoriteCount,
        (SELECT COUNT(*) FROM UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagCount,
        -- Time to accepted answer in hours
        EXTRACT(EPOCH FROM (pa.CreationDate - p.CreationDate)) / 3600.0 AS HoursToAcceptedAnswer,
        -- Running total of score for posts by the same user over time
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserCumulativeScore,
        -- Rank of post score within each tag
        RANK() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS RankInTag
    FROM Posts p
    LEFT JOIN Posts pa ON p.AcceptedAnswerId = pa.Id
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.CommunityOwnedDate IS NULL
      AND p.ClosedDate IS NULL
),
UserRanking AS (
    -- Step 3: Combine user activity with post details and apply window functions for ranking.
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.UserCreationDate,
        ua.QuestionsAsked,
        ua.AnswersPosted,
        ua.GoldBadges,
        ua.SilverBadges,
        AVG(pd.Score) AS AvgPostScore,
        AVG(pd.HoursToAcceptedAnswer) AS AvgHoursToAcceptedAnswer,
        -- Calculate a complex "Influence Score"
        (LOG(ua.Reputation + 1) * (ua.AnswersPosted + 1) * (ua.GoldBadges * 10 + ua.SilverBadges * 5 + ua.BronzeBadges)) / (EXTRACT(EPOCH FROM (NOW() - ua.UserCreationDate)) / 86400.0) AS InfluenceScore,
        NTILE(100) OVER (ORDER BY (LOG(ua.Reputation + 1) * (ua.AnswersPosted + 1)) DESC) AS ReputationPercentile,
        LAG(ua.DisplayName, 1, 'N/A') OVER (ORDER BY ua.Reputation DESC) AS UserWithHigherRep,
        LEAD(ua.DisplayName, 1, 'N/A') OVER (ORDER BY ua.Reputation DESC) AS UserWithLowerRep
    FROM UserActivity ua
    JOIN PostDetails pd ON ua.UserId = pd.OwnerUserId
    WHERE pd.TagCount > 2 OR pd.FavoriteCount > 10
    GROUP BY
        ua.UserId, ua.DisplayName, ua.Reputation, ua.UserCreationDate, ua.QuestionsAsked,
        ua.AnswersPosted, ua.TotalAnswerScore, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges
)
-- Final Selection: Combine results from different user segments using a UNION and apply final filtering/formatting.
(
    -- Segment 1: Top 100 influential users based on our calculated score.
    SELECT
        ur.UserId,
        ur.DisplayName,
        ur.Reputation,
        'Influential User' AS UserCategory,
        ur.InfluenceScore,
        ur.ReputationPercentile,
        ur.AvgHoursToAcceptedAnswer,
        CONCAT(
            'User ''', ur.DisplayName, ''' (Rep: ', ur.Reputation, ') has asked ', ur.QuestionsAsked,
            ' questions and posted ', ur.AnswersPosted, ' answers. ',
            'Belongs to Rep Percentile: ', ur.ReputationPercentile
        ) AS ProfileSummary,
        (
            SELECT STRING_AGG(b.Name, ', ')
            FROM (SELECT Name FROM Badges WHERE UserId = ur.UserId AND Class = 1 ORDER BY Date DESC LIMIT 3) b
        ) AS RecentGoldBadges
    FROM UserRanking ur
    WHERE ur.Reputation > (SELECT AVG(Reputation) FROM Users) AND ur.InfluenceScore > 0.1
    ORDER BY ur.InfluenceScore DESC
    LIMIT 100
)
UNION ALL
(
    -- Segment 2: "Specialists" - users with high-ranking posts in a specific, less common tag.
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        'Tag Specialist' AS UserCategory,
        pd.Score * 1.0 AS InfluenceScore,
        NULL AS ReputationPercentile,
        pd.HoursToAcceptedAnswer,
        CONCAT(
            'Specialist in tag ''', t.TagName, ''' with top post (ID: ', pd.PostId,
            ') scoring ', pd.Score
        ) AS ProfileSummary,
        NULL AS RecentGoldBadges
    FROM PostDetails pd
    JOIN Users u ON pd.OwnerUserId = u.Id
    JOIN Tags t ON pd.Tags LIKE '%' || t.TagName || '%'
    WHERE pd.RankInTag <= 3
      AND t.Count < (SELECT AVG(Count) FROM Tags) -- Less common tags
      AND t.TagName NOT IN ('discussion', 'feature-request', 'bug')
      AND NOT EXISTS (
          -- Correlated subquery: Ensure this is not one of the already selected influential users
          SELECT 1
          FROM UserRanking ur_inner
          WHERE ur_inner.UserId = u.Id
            AND ur_inner.InfluenceScore > 0.1
      )
    ORDER BY pd.Score DESC
    LIMIT 50
);
