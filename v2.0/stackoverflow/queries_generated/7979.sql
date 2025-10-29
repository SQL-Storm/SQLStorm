-- {"query": "7979.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2726} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate)) as DaysSinceLastPost,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        COALESCE(SUM(p.CommentCount), 0) as TotalComments,
        STRING_AGG(DISTINCT CASE 
            WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN 
                TRIM(BOTH '<>' FROM REGEXP_SUBSTR(p.Tags, '[^<>]+', 1, 1))
            ELSE NULL 
        END, ', ') as FirstTag,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        LastPostDate,
        DaysSinceLastPost,
        TotalScore,
        TotalViews,
        TotalComments,
        FirstTag,
        MedianScore,
        RANK() OVER (ORDER BY TotalScore DESC) as ScoreRank,
        RANK() OVER (ORDER BY TotalPosts DESC) as PostRank,
        RANK() OVER (ORDER BY Badges DESC) as BadgeRank
    FROM UserActivityStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END as PostTypeDesc,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            WHEN p.Score >= 10 THEN 'Low'
            ELSE 'Very Low'
        END as ScoreLevel,
        CASE 
            WHEN p.OwnerUserId IS NULL THEN 'Community Wiki'
            ELSE 'User Post'
        END as PostOwnership,
        COALESCE(p.Tags, '') as TagsList,
        COALESCE(p.Body, '') as BodyContent,
        LENGTH(p.Body) as BodyLength,
        LENGTH(p.Tags) as TagsLength,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as DaysOld,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)), 
            0
        ) as VoteCount,
        COALESCE(
            (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8), 
            0
        ) as AvgBounty,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL AND p.AnswerCount > 0 THEN 'Unanswered'
            WHEN p.PostTypeId = 1 THEN 'No Answers Yet'
            ELSE 'N/A'
        END as QuestionStatus,
        CASE 
            WHEN COALESCE(p.ClosedDate, '1900-01-01') != '1900-01-01' THEN 'Closed'
            WHEN COALESCE(p.CommunityOwnedDate, '1900-01-01') != '1900-01-01' THEN 'Community Owned'
            WHEN p.PostTypeId IN (1, 2) AND COALESCE(p.Score, 0) < 0 THEN 'Low Score'
            ELSE 'Active'
        END as PostStatus,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostOrder,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.Score DESC) as ScorePercentile
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Id IS NOT NULL
),
DetailedAnalysis AS (
    SELECT 
        pa.*,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg'
            WHEN pa.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Avg'
            ELSE 'Avg'
        END as AvgComparison,
        ROW_NUMBER() OVER (ORDER BY pa.Score DESC, pa.ViewCount DESC) as OverallRank,
        RANK() OVER (PARTITION BY pa.PostTypeId ORDER BY pa.Score DESC) as TypeRank,
        NTH_VALUE(pa.Title, 1) OVER (
            PARTITION BY pa.PostTypeId 
            ORDER BY pa.Score DESC 
            RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) as TopTitleByType,
        NTILE(10) OVER (ORDER BY pa.Score DESC) as ScoreDecile
    FROM PostAnalysis pa
),
TagAnalysis AS (
    SELECT 
        ta.Id,
        ta.TagName,
        ta.Count,
        ta.ExcerptPostId,
        ta.WikiPostId,
        ta.IsModeratorOnly,
        ta.IsRequired,
        COALESCE(p.Title, 'No Title') as TagTitle,
        COALESCE(p.Body, 'No Body') as TagBody,
        CASE 
            WHEN ta.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN ta.Count < (SELECT AVG(Count) FROM Tags) THEN 'Rare'
            ELSE 'Average'
        END as PopularityLevel,
        DENSE_RANK() OVER (ORDER BY ta.Count DESC) as PopularityRank
    FROM Tags ta
    LEFT JOIN Posts p ON ta.WikiPostId = p.Id
),
FinalAnalysis AS (
    SELECT 
        du.PostId,
        du.PostTypeId,
        du.PostTypeDesc,
        du.Title,
        du.OwnerName,
        du.OwnerUserId,
        du.Score,
        du.ViewCount,
        du.AnswerCount,
        du.ScoreLevel,
        du.PostStatus,
        du.ScorePercentile,
        du.ScoreRank,
        du.TypeRank,
        du.ScoreDecile,
        du.DaysOld,
        du.TagsList,
        du.BodyLength,
        du.TagsLength,
        du.VoteCount,
        du.AvgBounty,
        du.AvgComparison,
        du.TopTitleByType,
        du.QuestionStatus,
        CASE 
            WHEN du.Score > 100 AND du.ViewCount > 1000 THEN 'Hot'
            WHEN du.Score > 50 AND du.ViewCount > 500 THEN 'Trending'
            WHEN du.Score > 20 THEN 'Regular'
            WHEN du.Score < 0 THEN 'Problematic'
            ELSE 'Low Engagement'
        END as EngagementLevel,
        COALESCE(ta.TagName, 'N/A') as AssociatedTag,
        ta.PopularityLevel,
        ta.PopularityRank,
        CASE 
            WHEN du.PostTypeId = 1 AND du.AnswerCount = 0 THEN 'Unanswered Question'
            WHEN du.PostTypeId = 1 AND du.AnswerCount > 0 AND du.AcceptedAnswerId IS NULL THEN 'Answered Question'
            WHEN du.PostTypeId = 1 AND du.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer'
            WHEN du.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as ContentClassification,
        ROW_NUMBER() OVER (ORDER BY du.Score DESC, du.ViewCount DESC, du.CreationDate DESC) as FinalRank
    FROM DetailedAnalysis du
    LEFT JOIN TagAnalysis ta ON COALESCE(du.TagsList, '') LIKE '%' || COALESCE(ta.TagName, '') || '%'
    WHERE du.PostId IS NOT NULL
)
SELECT 
    fa.PostId,
    fa.PostTypeId,
    fa.PostTypeDesc,
    fa.Title,
    fa.OwnerName,
    fa.OwnerUserId,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.ScoreLevel,
    fa.PostStatus,
    fa.ScorePercentile,
    fa.ScoreRank,
    fa.TypeRank,
    fa.ScoreDecile,
    fa.DaysOld,
    fa.TagsList,
    fa.BodyLength,
    fa.TagsLength,
    fa.VoteCount,
    fa.AvgBounty,
    fa.AvgComparison,
    fa.TopTitleByType,
    fa.QuestionStatus,
    fa.EngagementLevel,
    fa.AssociatedTag,
    fa.PopularityLevel,
    fa.PopularityRank,
    fa.ContentClassification,
    fa.FinalRank,
    CASE 
        WHEN fa.Score > (SELECT AVG(Score) FROM Posts) THEN 1
        WHEN fa.Score < (SELECT AVG(Score) FROM Posts) THEN -1
        ELSE 0
    END as ScoreDirection,
    ROUND(
        (fa.Score * 0.5) + (fa.ViewCount * 0.3) + (fa.AnswerCount * 0.2), 
        2
    ) as EngagementScore,
    CASE 
        WHEN fa.Score > 100 AND fa.ViewCount > 1000 AND fa.AnswerCount > 1 THEN 'Viral Potential'
        WHEN fa.Score > 50 AND fa.ViewCount > 500 THEN 'Potential Viral'
        WHEN fa.Score > 20 THEN 'Standard'
        ELSE 'Low Impact'
    END as PublicationLevel,
    COALESCE(
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = fa.PostId), 
        0
    ) as CommentCount,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = fa.PostId AND v.VoteTypeId IN (1, 2, 3)), 
        0
    ) as TotalVotes,
    CASE 
        WHEN fa.Score > 100 THEN 'High Impact'
        WHEN fa.Score > 50 THEN 'Medium Impact'
        WHEN fa.Score > 10 THEN 'Low Impact'
        ELSE 'Minimal Impact'
    END as ImpactLevel,
    COALESCE(
        (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = fa.PostId), 
        '1900-01-01'
    ) as LastVoteDate,
    COALESCE(
        (SELECT MIN(v.CreationDate) FROM Votes v WHERE v.PostId = fa.PostId), 
        '1900-01-01'
    ) as FirstVoteDate,
    DATEDIFF(
        COALESCE((SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = fa.PostId), CURRENT_TIMESTAMP),
        COALESCE((SELECT MIN(v.CreationDate) FROM Votes v WHERE v.PostId = fa.PostId), '1900-01-01')
    ) as VoteLifetimeDays
FROM FinalAnalysis fa
WHERE fa.PostId IS NOT NULL
  AND (fa.Score >= 5 OR fa.ViewCount >= 100 OR fa.AnswerCount >= 1)
  AND (fa.PostStatus IN ('Active', 'Closed', 'Community Owned') OR fa.QuestionStatus IN ('Answered', 'Accepted Answer'))
ORDER BY fa.FinalRank ASC, fa.Score DESC, fa.ViewCount DESC, fa.CreationDate DESC
LIMIT 1000;