-- {"query": "7316.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2140}
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS WikiPosts,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS TotalAnswerScore,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 0) AS AvgQuestionScore,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) AS AvgAnswerScore,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT CASE WHEN c.Score > 0 THEN c.Id END) AS PositiveComments,
    COUNT(DISTINCT CASE WHEN c.Score < 0 THEN c.Id END) AS NegativeComments,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteVotes,
    COALESCE(MAX(p.CreationDate), TIMESTAMP '1900-01-01') AS LastPostDate,
    COALESCE(MAX(c.CreationDate), TIMESTAMP '1900-01-01') AS LastCommentDate,
    COALESCE(MAX(v.CreationDate), TIMESTAMP '1900-01-01') AS LastVoteDate,
    COALESCE(MAX(b.Date), TIMESTAMP '1900-01-01') AS LastBadgeDate,
    EXTRACT(YEAR FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate)) AS AccountAgeYears,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 100 AND COUNT(DISTINCT b.Id) > 50 THEN 'Active Contributor'
        WHEN COUNT(DISTINCT p.Id) > 50 AND COUNT(DISTINCT b.Id) > 25 THEN 'Regular Contributor'
        WHEN COUNT(DISTINCT p.Id) > 10 AND COUNT(DISTINCT b.Id) > 5 THEN 'Occasional Contributor'
        ELSE 'New Member'
    END AS ContributionTier,
    ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) DESC) AS TopQuestionScoreRank,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeCountRank,
    (SELECT AVG(p2.Score) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
     AND p2.PostTypeId = 1) AS AvgQuestionScoreByUser,
    (SELECT COUNT(*) 
     FROM Posts p3 
     WHERE p3.OwnerUserId = u.Id 
     AND p3.PostTypeId = 1 
     AND p3.Score > (
         SELECT AVG(p4.Score) 
         FROM Posts p4 
         WHERE p4.PostTypeId = 1 
         AND p4.OwnerUserId IS NOT NULL
     )
    ) AS QuestionsAboveAverageScore,
    (
        WITH TagAnalysis AS (
            SELECT 
                t.TagName,
                COUNT(DISTINCT p.Id) AS QuestionCount,
                AVG(p.Score) AS AvgScore,
                ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS TagRank
            FROM Tags t
            JOIN Posts p ON POSITION('<' || t.TagName || '>' IN COALESCE(p.Tags, '')) > 0
            WHERE p.OwnerUserId = u.Id 
            AND p.PostTypeId = 1
            GROUP BY t.TagName, t.Id
        )
        SELECT STRING_AGG(CONCAT(TagName, ':', QuestionCount, ' q, ', ROUND(AvgScore, 2), ' avg score'), '; ')
        FROM TagAnalysis 
        WHERE TagRank <= 5
    ) AS TopTagsAnalysis,
    (
        CASE WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
             AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 
             THEN 'Both Questions and Answers' 
             WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
             THEN 'Question Only'
             WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 
             THEN 'Answer Only'
             ELSE 'No Posts'
        END
    ) AS PostTypeCategory,
    CASE 
        WHEN SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) IS NOT NULL 
             AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
        THEN ROUND(
            SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) * 
            COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) / 
            NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0),
            2
        )
        ELSE 0 
    END AS ScoreProductivityMetric,
    CASE 
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' 
        THEN 'Website: ' || SUBSTRING(u.WebsiteUrl FROM 1 FOR 30) || '...'
        WHEN u.Location IS NOT NULL AND u.Location <> ''
        THEN 'Location: ' || u.Location
        ELSE 'No Profile Info'
    END AS ProfileSummary,
    (
        SELECT CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 5000 THEN 'Advanced'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            WHEN u.Reputation >= 100 THEN 'Beginner'
            ELSE 'Newbie'
        END
    ) AS ReputationBand,
    COALESCE(
        EXTRACT(DAY FROM (NULLIF(MAX(v.CreationDate), TIMESTAMP '1900-01-01') - NULLIF(MAX(p.CreationDate), TIMESTAMP '1900-01-01'))),
        0
    ) AS DaysBetweenLastPostAndVote,
    (
        SELECT COUNT(DISTINCT ph.Id) 
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id 
        AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19)
    ) AS ModerationActions,
    CASE 
        WHEN (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.Score > 50) >= 5
        AND (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.ViewCount > 1000) >= 2
        THEN 'High Impact Contributor'
        WHEN (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.Score > 10) >= 10
        THEN 'Helpful Contributor'
        ELSE 'Standard Contributor'
    END AS ImpactAnalysis,
    CASE 
        WHEN COUNT(DISTINCT b.Id) > 0 AND COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) >= 10 THEN 'Legendary Contributor'
        WHEN COUNT(DISTINCT b.Id) > 0 AND COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) >= 5 THEN 'Veteran Contributor'
        ELSE 'Regular Contributor'
    END AS RecognitionTier
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
WHERE u.Reputation >= 100
AND u.CreationDate < TIMESTAMP '2010-01-01'
AND u.DisplayName IS NOT NULL
AND u.DisplayName <> ''
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.WebsiteUrl, u.Location
HAVING COUNT(DISTINCT p.Id) >= 10
   AND (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0)
ORDER BY TotalPosts DESC
LIMIT 1000;