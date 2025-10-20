-- {"query": "29042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2993} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(CAST(p.Score AS FLOAT)) AS AvgScore,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ' | ') AS QuestionTitles,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 2 THEN LEFT(p.Body, 50) END, ' | ') AS AnswerSnippets,
        COUNT(DISTINCT CASE WHEN p.Score > 10 THEN p.Id END) AS HighScorePosts,
        COUNT(DISTINCT CASE WHEN p.ViewCount > 1000 THEN p.Id END) AS PopularPosts,
        COUNT(DISTINCT CASE WHEN p.CreationDate >= '2022-01-01' THEN p.Id END) AS RecentPosts,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS PostRank,
        LAG(p.CreationDate, 1) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS PrevPostDate,
        DATEDIFF(DAY, LAG(p.CreationDate, 1) OVER (PARTITION BY u.Id ORDER BY p.CreationDate), p.CreationDate) AS DaysSinceLastPost
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Accepted Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDescription,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.ViewCount) AS ViewPercentile,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')
            ELSE ARRAY[]::TEXT[]
        END AS TagArray,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementCount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.Title, p.Body, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, p.PostTypeId, p.AnswerCount, p.CommentCount, p.Tags
),
CombinedUserStats AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.LastPostDate,
        uas.AvgScore,
        uas.QuestionTitles,
        uas.AnswerSnippets,
        uas.HighScorePosts,
        uas.PopularPosts,
        uas.RecentPosts,
        uas.PostRank,
        uas.DaysSinceLastPost,
        CASE 
            WHEN uas.Reputation > 10000 THEN 'Elite'
            WHEN uas.Reputation > 5000 THEN 'Veteran'
            WHEN uas.Reputation > 1000 THEN 'Experienced'
            ELSE 'Beginner'
        END AS RepTier,
        CASE 
            WHEN uas.Questions > 100 THEN 'Expert Questioner'
            WHEN uas.Questions > 50 THEN 'Frequent Questioner'
            WHEN uas.Questions > 10 THEN 'Occasional Questioner'
            ELSE 'New Questioner'
        END AS QuestionerProfile,
        CASE 
            WHEN uas.Answers > 200 THEN 'Expert Answerer'
            WHEN uas.Answers > 100 THEN 'Frequent Answerer'
            WHEN uas.Answers > 20 THEN 'Occasional Answerer'
            ELSE 'New Answerer'
        END AS AnswererProfile,
        ROW_NUMBER() OVER (ORDER BY uas.Reputation DESC) AS RankByReputation,
        ROW_NUMBER() OVER (ORDER BY uas.TotalPosts DESC) AS RankByActivity
    FROM UserActivityStats uas
    WHERE uas.Reputation > 0
),
ComplexPostAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.PostTypeDescription,
        pa.VoteCount,
        pa.UpVotes,
        pa.DownVotes,
        pa.ScoreRank,
        pa.ViewPercentile,
        pa.TagArray,
        pa.EngagementCount,
        CASE 
            WHEN pa.Score > 50 THEN 'High Impact'
            WHEN pa.Score > 20 THEN 'Medium Impact'
            WHEN pa.Score > 0 THEN 'Low Impact'
            ELSE 'Negative Impact'
        END AS ImpactLevel,
        CASE 
            WHEN pa.ViewCount > 5000 THEN 'Viral'
            WHEN pa.ViewCount > 1000 THEN 'Popular'
            WHEN pa.ViewCount > 100 THEN 'Noticeable'
            ELSE 'Obscure'
        END AS PopularityLevel,
        COALESCE(
            (SELECT AVG(Score) FROM Posts p2 WHERE p2.PostTypeId = 1 AND p2.OwnerUserId = pa.OwnerUserId), 
            0
        ) AS AvgScoreByOwner,
        COALESCE(
            (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = pa.PostId AND ph.PostHistoryTypeId IN (1, 4, 5, 6)), 
            0
        ) AS EditCount,
        CASE 
            WHEN pa.TagArray IS NOT NULL AND ARRAY_LENGTH(pa.TagArray, 1) > 0 THEN 
                ARRAY_TO_STRING(pa.TagArray, ', ')
            ELSE 'No Tags'
        END AS FormattedTags,
        CASE 
            WHEN pa.Body IS NOT NULL THEN LENGTH(pa.Body)
            ELSE 0
        END AS BodyLength,
        CASE 
            WHEN pa.Title IS NOT NULL THEN UPPER(pa.Title)
            ELSE 'UNKNOWN TITLE'
        END AS UpperTitle,
        CASE 
            WHEN pa.OwnerUserId IS NOT NULL THEN 
                (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = pa.OwnerUserId AND p3.PostTypeId = 1)
            ELSE 0
        END AS UserQuestionCount,
        CASE 
            WHEN pa.OwnerUserId IS NOT NULL THEN 
                (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = pa.OwnerUserId AND p4.PostTypeId = 2)
            ELSE 0
        END AS UserAnswerCount
    FROM PostAnalysis pa
)
SELECT 
    COALESCE(cu.UserId, 0) AS UserId,
    COALESCE(cu.DisplayName, 'Unknown') AS DisplayName,
    COALESCE(cu.Reputation, 0) AS Reputation,
    COALESCE(cu.TotalPosts, 0) AS TotalPosts,
    COALESCE(cu.Questions, 0) AS Questions,
    COALESCE(cu.Answers, 0) AS Answers,
    COALESCE(cu.Comments, 0) AS Comments,
    COALESCE(cu.Badges, 0) AS Badges,
    COALESCE(cu.LastPostDate, '1900-01-01') AS LastPostDate,
    COALESCE(cu.AvgScore, 0) AS AvgScore,
    COALESCE(cu.QuestionTitles, '') AS QuestionTitles,
    COALESCE(cu.AnswerSnippets, '') AS AnswerSnippets,
    COALESCE(cu.HighScorePosts, 0) AS HighScorePosts,
    COALESCE(cu.PopularPosts, 0) AS PopularPosts,
    COALESCE(cu.RecentPosts, 0) AS RecentPosts,
    COALESCE(cu.PostRank, 0) AS PostRank,
    COALESCE(cu.DaysSinceLastPost, 0) AS DaysSinceLastPost,
    COALESCE(cu.RepTier, 'Unknown') AS RepTier,
    COALESCE(cu.QuestionerProfile, 'Unknown') AS QuestionerProfile,
    COALESCE(cu.AnswererProfile, 'Unknown') AS AnswererProfile,
    COALESCE(cu.RankByReputation, 0) AS RankByReputation,
    COALESCE(cu.RankByActivity, 0) AS RankByActivity,
    COALESCE(cpa.PostId, 0) AS PostId,
    COALESCE(cpa.Title, 'Unknown') AS PostTitle,
    COALESCE(cpa.Score, 0) AS PostScore,
    COALESCE(cpa.ViewCount, 0) AS PostViewCount,
    COALESCE(cpa.CreationDate, '1900-01-01') AS PostCreationDate,
    COALESCE(cpa.OwnerUserId, 0) AS PostOwnerUserId,
    COALESCE(cpa.PostTypeDescription, 'Unknown') AS PostTypeDescription,
    COALESCE(cpa.VoteCount, 0) AS VoteCount,
    COALESCE(cpa.UpVotes, 0) AS UpVotes,
    COALESCE(cpa.DownVotes, 0) AS DownVotes,
    COALESCE(cpa.ScoreRank, 0) AS ScoreRank,
    COALESCE(cpa.ViewPercentile, 0) AS ViewPercentile,
    COALESCE(cpa.TagArray, ARRAY[]::TEXT[]) AS TagArray,
    COALESCE(cpa.EngagementCount, 0) AS EngagementCount,
    COALESCE(cpa.ImpactLevel, 'Unknown') AS ImpactLevel,
    COALESCE(cpa.PopularityLevel, 'Unknown') AS PopularityLevel,
    COALESCE(cpa.AvgScoreByOwner, 0) AS AvgScoreByOwner,
    COALESCE(cpa.EditCount, 0) AS EditCount,
    COALESCE(cpa.FormattedTags, 'No Tags') AS FormattedTags,
    COALESCE(cpa.BodyLength, 0) AS BodyLength,
    COALESCE(cpa.UpperTitle, 'UNKNOWN TITLE') AS UpperTitle,
    COALESCE(cpa.UserQuestionCount, 0) AS UserQuestionCount,
    COALESCE(cpa.UserAnswerCount, 0) AS UserAnswerCount,
    CASE WHEN cu.UserId IS NULL THEN 1 ELSE 0 END AS IsMissingUser,
    CASE WHEN cpa.PostId IS NULL THEN 1 ELSE 0 END AS IsMissingPost,
    CASE WHEN cu.UserId IS NOT NULL AND cpa.PostId IS NOT NULL THEN 'Active' ELSE 'Inactive' END AS ActivityStatus,
    CASE WHEN cu.UserId IS NOT NULL AND cu.Reputation > 10000 THEN 1 ELSE 0 END AS IsElite,
    CASE WHEN cu.UserId IS NOT NULL AND cu.TotalPosts > 500 THEN 1 ELSE 0 END AS IsHighlyActive,
    CASE WHEN cpa.PostId IS NOT NULL AND cpa.ViewCount > 1000 THEN 1 ELSE 0 END AS IsPopularPost,
    CASE WHEN cpa.PostId IS NOT NULL AND cpa.Score > 50 THEN 1 ELSE 0 END AS IsHighImpactPost,
    CASE WHEN cu.UserId IS NOT NULL AND cu.RecentPosts > 10 THEN 1 ELSE 0 END AS IsRecentlyActive,
    CASE WHEN cu.UserId IS NOT NULL AND cu.Badges > 100 THEN 1 ELSE 0 END AS IsBadgeHunter,
    CASE WHEN cu.UserId IS NOT NULL AND cu.Comments > 1000 THEN 1 ELSE 0 END AS IsCommentativeUser,
    CASE WHEN cpa.PostId IS NOT NULL AND cpa.BodyLength > 1000 THEN 1 ELSE 0 END AS IsLongPost
FROM CombinedUserStats cu
FULL OUTER JOIN ComplexPostAnalysis cpa ON cu.UserId = cpa.OwnerUserId
WHERE (cu.UserId IS NOT NULL OR cpa.PostId IS NOT NULL)
AND (cu.Reputation IS NOT NULL OR cpa.Score IS NOT NULL)
AND (cu.Reputation > 0 OR (cpa.Score > 0 AND cpa.PostTypeDescription = 'Question'))
AND (
    cu.RepTier IN ('Elite', 'Veteran') 
    OR cpa.PopularityLevel IN ('Viral', 'Popular')
    OR (cu.UserQuestionCount > 50 AND cu.UserAnswerCount > 100)
    OR cpa.ImpactLevel IN ('High Impact', 'Medium Impact')
)
ORDER BY 
    CASE WHEN cu.UserId IS NOT NULL THEN cu.Reputation ELSE 0 END DESC,
    CASE WHEN cpa.PostId IS NOT NULL THEN cpa.Score ELSE 0 END DESC,
    cu.LastPostDate DESC,
    cpa.CreationDate DESC;