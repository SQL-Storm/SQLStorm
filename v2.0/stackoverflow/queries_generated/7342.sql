-- {"query": "7342.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2110} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LatestPostDate,
        MAX(c.CreationDate) as LatestCommentDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Active'
            ELSE 'Newbie'
        END as ReputationTier,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY u.Views DESC) as RankByViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        PostCount,
        CommentCount,
        BadgeCount,
        LatestPostDate,
        LatestCommentDate,
        ReputationTier,
        RankByReputation,
        RankByViews,
        CASE 
            WHEN PostCount > 100 AND CommentCount > 500 THEN 'Highly Engaged'
            WHEN PostCount > 50 AND CommentCount > 200 THEN 'Engaged'
            WHEN PostCount > 10 AND CommentCount > 50 THEN 'Moderately Engaged'
            ELSE 'Casual'
        END as EngagementLevel
    FROM UserActivityStats
    WHERE RankByReputation <= 1000
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END as Popularity,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Rated'
            WHEN p.Score > 50 THEN 'Well Rated'
            WHEN p.Score > 10 THEN 'Average Rated'
            ELSE 'Low Rated'
        END as Rating,
        CASE 
            WHEN p.AnswerCount > 50 THEN 'Highly Answered'
            WHEN p.AnswerCount > 10 THEN 'Moderately Answered'
            WHEN p.AnswerCount > 0 THEN 'Slightly Answered'
            ELSE 'Unanswered'
        END as AnswerStatus,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountFromComments,
        IIF(p.AcceptedAnswerId IS NOT NULL, 1, 0) as HasAcceptedAnswer,
        COALESCE(p.Tags, '') as TagsList,
        LEN(p.Tags) as TagsLength,
        TRIM(REPLACE(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ', '')) as CleanTags,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpVotesCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownVotesCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 4, 5, 6)) as EditCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score IS NOT NULL
),
CombinedAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.Views,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.ReputationTier,
        tu.RankByReputation,
        tu.RankByViews,
        tu.EngagementLevel,
        pc.PostId,
        pc.Title,
        pc.Score,
        pc.ViewCount,
        pc.AnswerCount,
        pc.CommentCount as PostCommentCount,
        pc.FavoriteCount,
        pc.CreationDate as PostCreationDate,
        pc.PostType,
        pc.Popularity,
        pc.Rating,
        pc.AnswerStatus,
        pc.CommentCountFromComments,
        pc.HasAcceptedAnswer,
        pc.TagsList,
        pc.TagsLength,
        pc.CleanTags,
        pc.UpVotesCount,
        pc.DownVotesCount,
        pc.EditCount,
        DATEDIFF(day, tu.LatestPostDate, GETDATE()) as DaysSinceLatestPost,
        DATEDIFF(day, tu.LatestCommentDate, GETDATE()) as DaysSinceLatestComment,
        COALESCE(tu.PostCount + tu.CommentCount + tu.BadgeCount, 0) as TotalActivityPoints,
        CASE 
            WHEN tu.PostCount > 0 AND CAST(pc.Score AS FLOAT) / CAST(tu.PostCount AS FLOAT) > 5 THEN 'High Value Contributor'
            WHEN tu.PostCount > 0 AND CAST(pc.Score AS FLOAT) / CAST(tu.PostCount AS FLOAT) > 2 THEN 'Value Contributor'
            WHEN tu.PostCount > 0 AND CAST(pc.Score AS FLOAT) / CAST(tu.PostCount AS FLOAT) >= 0 THEN 'Standard Contributor'
            ELSE 'Inactive'
        END as ContributionValue
    FROM TopUsers tu
    INNER JOIN PostComplexity pc ON tu.UserId = pc.OwnerUserId
    WHERE pc.ViewCount > 1000 OR pc.Score > 50 OR pc.AnswerCount > 10 OR (pc.CommentCountFromComments > 10 AND tu.RankByReputation <= 500)
    AND pc.CreationDate >= DATEADD(month, -12, GETDATE())
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    Views,
    PostCount,
    CommentCount,
    BadgeCount,
    ReputationTier,
    RankByReputation,
    RankByViews,
    EngagementLevel,
    PostId,
    Title,
    Score,
    ViewCount,
    AnswerCount,
    PostCommentCount,
    FavoriteCount,
    PostCreationDate,
    PostType,
    Popularity,
    Rating,
    AnswerStatus,
    CommentCountFromComments,
    HasAcceptedAnswer,
    TagsList,
    TagsLength,
    CleanTags,
    UpVotesCount,
    DownVotesCount,
    EditCount,
    DaysSinceLatestPost,
    DaysSinceLatestComment,
    TotalActivityPoints,
    ContributionValue,
    -- Calculated Metrics
    CAST(Score AS FLOAT) / NULLIF(PostCount, 0) as AvgScorePerPost,
    CAST(CommentCountFromComments AS FLOAT) / NULLIF(ViewCount, 0) as CommentToViewRatio,
    CAST(AnswerCount AS FLOAT) / NULLIF(PostCount, 0) as AnswerToPostRatio,
    CAST(UpVotesCount AS FLOAT) / NULLIF(DownVotesCount, 0) as UpToDownRatio,
    -- String manipulation and filtering
    CASE 
        WHEN CleanTags LIKE '%sql%' OR CleanTags LIKE '%database%' OR CleanTags LIKE '%query%' THEN 'SQL Related'
        WHEN CleanTags LIKE '%c%' OR CleanTags LIKE '%c++%' OR CleanTags LIKE '%programming%' THEN 'Programming Related'
        WHEN CleanTags LIKE '%python%' OR CleanTags LIKE '%data%' OR CleanTags LIKE '%analysis%' THEN 'Data Related'
        ELSE 'Other'
    END as TopicCategory,
    -- Complex predicate with multiple conditions
    CASE 
        WHEN (PostType = 'Question' AND AnswerCount >= 5 AND Score >= 20) OR 
             (PostType = 'Answer' AND Score >= 10 AND CommentCountFromComments >= 3) THEN 'High Quality'
        WHEN (PostType = 'Question' AND AnswerCount >= 2 AND Score >= 10) OR 
             (PostType = 'Answer' AND Score >= 5 AND CommentCountFromComments >= 1) THEN 'Moderate Quality'
        ELSE 'Low Quality'
    END as QualityLevel,
    -- Window function for ranking within groups
    ROW_NUMBER() OVER (PARTITION BY ReputationTier ORDER BY Score DESC) as ScoreRankInTier,
    RANK() OVER (ORDER BY TotalActivityPoints DESC) as ActivityRank,
    -- Set operator simulation using UNION
    (SELECT TOP 1 PostId FROM CombinedAnalysis ca2 WHERE ca2.UserId = CombinedAnalysis.UserId AND ca2.Score > 100 ORDER BY ca2.Score DESC) as TopScoringPostId
FROM CombinedAnalysis
WHERE 
    ViewCount > 500 
    AND (Score > 10 OR AnswerCount > 2 OR CommentCountFromComments > 5)
    AND ContributionValue IN ('High Value Contributor', 'Value Contributor', 'Standard Contributor')
    AND (RankByReputation <= 200 OR RankByViews <= 200)
    AND (PostType = 'Question' OR (PostType = 'Answer' AND HasAcceptedAnswer = 1))
ORDER BY 
    Reputation DESC,
    Score DESC,
    ViewCount DESC
OFFSET 0 ROWS
FETCH NEXT 2000 ROWS ONLY;