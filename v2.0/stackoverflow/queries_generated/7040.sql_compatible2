WITH PostStats AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostSequence,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalPostsByUser,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScoreByUser,
        CASE WHEN p.ParentId IS NULL THEN 'Question' ELSE 'Answer' END as PostTypeDesc,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        COALESCE(p.Tags, '') as CleanTags,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        CAST((EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400) AS INTEGER) as DaysActive
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate > TIMESTAMP '2022-01-01 00:00:00'
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate as UserCreationDate,
        COALESCE(u.WebsiteUrl, 'No Website') as Website,
        COALESCE(u.Location, 'Unknown Location') as Location,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Regular'
            ELSE 'Newbie'
        END as ReputationTier,
        COUNT(DISTINCT ps.PostId) as TotalPosts,
        SUM(ps.Score) as TotalScore,
        AVG(ps.Score) as AvgPostScore,
        MAX(ps.CreationDate) as LastPostDate,
        CAST((EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400) AS INTEGER) as DaysSinceRegistration
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.WebsiteUrl, u.Location
),
TagAnalysis AS (
    SELECT 
        t.Id as TagId,
        t.TagName,
        t.Count as TagCount,
        t.IsRequired,
        t.IsModeratorOnly,
        STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END, '; ') as QuestionTitles,
        STRING_AGG(CASE WHEN p.PostTypeId = 2 THEN p.Title ELSE NULL END, '; ') as AnswerTitles,
        COUNT(DISTINCT p.Id) as PostCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags IS NOT NULL AND p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.Count > 10
    GROUP BY t.Id, t.TagName, t.Count, t.IsRequired, t.IsModeratorOnly
),
ComplexPosts AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Tags,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.OwnerUserId,
        ps.PostTypeDesc,
        ps.ScoreCategory,
        ps.UserPostSequence,
        ps.TotalPostsByUser,
        ps.AvgScoreByUser,
        ps.DaysActive,
        CASE 
            WHEN ps.AnswerCount > 0 AND ps.Score > 0 THEN 'Active Question'
            WHEN ps.CommentCount > 0 AND ps.Score > 0 THEN 'Engaged Question'
            WHEN ps.Score = 0 AND ps.AnswerCount = 0 THEN 'Unanswered' 
            ELSE 'Other'
        END as QuestionStatus,
        CASE 
            WHEN ps.Score > 0 AND ps.AnswerCount > 0 THEN 'Answered'
            WHEN ps.Score > 0 AND ps.AnswerCount = 0 THEN 'Unanswered'
            ELSE 'No Score'
        END as AnswerStatus,
        CASE 
            WHEN ps.Score > 100 THEN 'Popular'
            WHEN ps.Score > 50 THEN 'Moderate'
            ELSE 'Normal'
        END as Popularity,
        COALESCE(UPPER(SUBSTRING(ps.Title FROM 1 FOR 1)), 'N') as FirstLetter,
        CHAR_LENGTH(ps.Title) as TitleLength,
        (CASE WHEN ps.Tags IS NOT NULL AND CHAR_LENGTH(ps.Tags) > 0 THEN 1 ELSE 0 END) as HasTags,
        ps.CreationDate,
        ps.LastActivityDate
    FROM PostStats ps
    WHERE ps.Score >= 0
),
FinalReport AS (
    SELECT 
        cp.PostId,
        cp.Title,
        cp.Tags,
        cp.Score,
        cp.ViewCount,
        cp.AnswerCount,
        cp.CommentCount,
        cp.FavoriteCount,
        cp.OwnerUserId,
        cp.PostTypeDesc,
        cp.ScoreCategory,
        cp.UserPostSequence,
        cp.TotalPostsByUser,
        cp.AvgScoreByUser,
        cp.DaysActive,
        cp.QuestionStatus,
        cp.AnswerStatus,
        cp.Popularity,
        cp.FirstLetter,
        cp.TitleLength,
        cp.HasTags,
        cp.CreationDate,
        cp.LastActivityDate,
        ua.DisplayName as OwnerName,
        ua.Reputation as OwnerReputation,
        ua.TotalPosts as OwnerTotalPosts,
        ua.TotalScore as OwnerTotalScore,
        ua.AvgPostScore as OwnerAvgPostScore,
        ta.TagName,
        ta.TagCount,
        ta.PostCount,
        ta.TotalScore as TagTotalScore,
        ta.AvgScore as TagAvgScore,
        CASE 
            WHEN cp.Score >= cp.AvgScoreByUser AND cp.AnswerCount >= 1 THEN 'Above Average with Answers'
            WHEN cp.Score >= cp.AvgScoreByUser THEN 'Above Average'
            WHEN cp.AnswerCount >= 1 THEN 'Answered'
            ELSE 'Below Average'
        END as PerformanceLevel,
        ROUND(
            (cp.Score + cp.AnswerCount + cp.CommentCount + cp.FavoriteCount) / 
            NULLIF(cp.ViewCount, 0) * 100.0, 
            2
        ) as EngagementRatio,
        ROW_NUMBER() OVER (ORDER BY (cp.Score + cp.AnswerCount + cp.CommentCount + cp.FavoriteCount) DESC) as OverallRank
    FROM ComplexPosts cp
    LEFT JOIN UserActivity ua ON cp.OwnerUserId = ua.UserId
    LEFT JOIN TagAnalysis ta ON cp.Tags IS NOT NULL AND cp.Tags LIKE '%' || ta.TagName || '%'
    WHERE cp.DaysActive <= 365
)
SELECT 
    fr.PostId,
    fr.Title,
    fr.Tags,
    fr.Score,
    fr.ViewCount,
    fr.AnswerCount,
    fr.CommentCount,
    fr.FavoriteCount,
    fr.OwnerName,
    fr.OwnerReputation,
    fr.OwnerTotalPosts,
    fr.OwnerTotalScore,
    fr.OwnerAvgPostScore,
    fr.TagName,
    fr.TagCount,
    fr.PostCount,
    fr.TagTotalScore,
    fr.TagAvgScore,
    fr.QuestionStatus,
    fr.AnswerStatus,
    fr.Popularity,
    fr.FirstLetter,
    fr.TitleLength,
    fr.HasTags,
    fr.CreationDate,
    fr.LastActivityDate,
    fr.PerformanceLevel,
    fr.EngagementRatio,
    fr.OverallRank,
    CASE 
        WHEN fr.Score > 200 AND fr.AnswerCount > 5 THEN 'High Impact'
        WHEN fr.Score > 100 THEN 'Medium Impact'
        WHEN fr.AnswerCount > 2 THEN 'Well Answered'
        ELSE 'Standard'
    END as ContentImpact,
    CASE 
        WHEN fr.OwnerReputation > 1000 THEN 'Established Contributor'
        WHEN fr.OwnerReputation > 100 THEN 'Regular Contributor'
        ELSE 'Emerging Contributor'
    END as ContributorTier,
    CASE 
        WHEN fr.TagCount > 1000 THEN 'Popular Tag'
        WHEN fr.TagCount > 100 THEN 'Moderate Tag'
        ELSE 'Niche Tag'
    END as TagDensity,
    CASE 
        WHEN fr.EngagementRatio > 5 THEN 'Highly Engaged'
        WHEN fr.EngagementRatio > 2 THEN 'Moderately Engaged'
        ELSE 'Low Engagement'
    END as EngagementLevel,
    CASE 
        WHEN fr.OwnerAvgPostScore > 5 THEN 'High Scoring Author'
        WHEN fr.OwnerAvgPostScore > 2 THEN 'Moderate Scoring Author'
        ELSE 'Low Scoring Author'
    END as AuthorProductivity,
    CASE 
        WHEN fr.OwnerTotalPosts > 100 THEN 'Veteran Poster'
        WHEN fr.OwnerTotalPosts > 50 THEN 'Active Poster'
        WHEN fr.OwnerTotalPosts > 10 THEN 'Regular Poster'
        ELSE 'Occasional Poster'
    END as PosterFrequency
FROM FinalReport fr
WHERE fr.PostId IS NOT NULL
  AND (fr.Score > 0 OR fr.AnswerCount > 0 OR fr.CommentCount > 0)
  AND (fr.Title IS NOT NULL AND CHAR_LENGTH(fr.Title) > 0)
ORDER BY fr.OverallRank
LIMIT 1000;