-- {"query": "7722.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2981} 
WITH PostStats AS (
    SELECT 
        p.Id,
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
        COALESCE(p.Body, '') AS Body,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Low'
            ELSE 'Average'
        END AS ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS GlobalRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) AS NextScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsByUser
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserEngagement AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        AVG(ps.Score) AS AvgScore,
        MAX(ps.CreationDate) AS LastPostDate,
        CASE 
            WHEN COUNT(DISTINCT ps.Id) > 100 THEN 'Veteran'
            WHEN COUNT(DISTINCT ps.Id) > 50 THEN 'Experienced'
            WHEN COUNT(DISTINCT ps.Id) > 10 THEN 'Regular'
            ELSE 'New'
        END AS UserLevel,
        COALESCE(SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(SUM(ps.Score), 0) AS TotalScore,
        COALESCE(SUM(CASE WHEN ps.Score > 0 THEN ps.Score ELSE 0 END), 0) AS PositiveScore,
        COALESCE(SUM(CASE WHEN ps.Score < 0 THEN ps.Score ELSE 0 END), 0) AS NegativeScore
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagAnalysis AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        t.IsRequired,
        t.IsModeratorOnly,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Rare'
            ELSE 'Average'
        END AS PopularityLevel,
        NTILE(4) OVER (ORDER BY t.Count DESC) AS Quartile,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) AS PreviousCount,
        LEAD(t.Count, 1) OVER (ORDER BY t.Count DESC) AS NextCount
    FROM Tags t
),
ComplexPostQueries AS (
    SELECT 
        ps.Id AS PostId,
        ps.Title,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.PostType,
        ps.ScoreCategory,
        ps.UserPostRank,
        ps.GlobalRank,
        ps.ScoreRank,
        ps.TotalPostsByUser,
        ps.PreviousScore,
        ps.NextScore,
        CASE 
            WHEN ps.Score > 100 THEN 'Very High'
            WHEN ps.Score > 50 THEN 'High'
            WHEN ps.Score > 10 THEN 'Medium'
            WHEN ps.Score > 0 THEN 'Low'
            ELSE 'Negative'
        END AS ScoreLevel,
        COALESCE(
            CASE 
                WHEN ps.PostType = 'Question' AND ps.AnswerCount > 0 THEN
                    CAST(ps.AnswerCount AS FLOAT) / CAST(ps.ViewCount AS FLOAT) * 100
                ELSE NULL
            END, 0) AS AnswerPerViewRatio,
        CASE 
            WHEN ps.CommentCount IS NOT NULL THEN 
                CASE 
                    WHEN ps.ViewCount IS NOT NULL AND ps.ViewCount > 0 THEN 
                        CAST(ps.CommentCount AS FLOAT) / CAST(ps.ViewCount AS FLOAT) * 100
                    ELSE 0
                END
            ELSE 0
        END AS CommentPerViewRatio,
        COALESCE(
            CASE 
                WHEN ps.PostType = 'Question' AND ps.Score IS NOT NULL THEN ps.Score * 10
                WHEN ps.PostType = 'Answer' AND ps.Score IS NOT NULL THEN ps.Score * 5
                ELSE 0
            END, 0) AS AdjustedScore
    FROM PostStats ps
),
FilteredPosts AS (
    SELECT 
        cp.*,
        ue.TotalPosts,
        ue.AvgScore,
        ue.UserLevel,
        (SELECT COUNT(*) FROM Votes v 
         WHERE v.PostId = cp.PostId 
         AND v.VoteTypeId IN (2, 3)) AS VoteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cp.PostId) AS CommentCount,
        (
            SELECT MAX(CreationDate)
            FROM PostHistory ph
            WHERE ph.PostId = cp.PostId
            AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20)
        ) AS LastMajorEventDate,
        (
            SELECT 
                CASE 
                    WHEN MAX(ph.PostHistoryTypeId) = 12 THEN 'Deleted'
                    WHEN MAX(ph.PostHistoryTypeId) = 11 THEN 'Reopened'
                    WHEN MAX(ph.PostHistoryTypeId) = 10 THEN 'Closed'
                    WHEN MAX(ph.PostHistoryTypeId) = 16 THEN 'Community Owned'
                    ELSE 'Normal'
                END
            FROM PostHistory ph
            WHERE ph.PostId = cp.PostId
            AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20)
        ) AS PostStatus,
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            WHERE pl.PostId = cp.PostId
            AND pl.LinkTypeId = 3
        ) AS DuplicateCount
    FROM ComplexPostQueries cp
    LEFT JOIN UserEngagement ue ON cp.OwnerUserId = ue.UserId
    WHERE cp.ScoreCategory IN ('High', 'Low')
    AND cp.PostType = 'Question'
    AND cp.GlobalRank <= 1000
),
CombinedResults AS (
    SELECT 
        fp.PostId,
        fp.Title,
        fp.OwnerUserId,
        fp.Score,
        fp.ViewCount,
        fp.AnswerCount,
        fp.CommentCount,
        fp.FavoriteCount,
        fp.PostType,
        fp.ScoreCategory,
        fp.UserPostRank,
        fp.GlobalRank,
        fp.ScoreRank,
        fp.TotalPostsByUser,
        fp.ScoreLevel,
        fp.AnswerPerViewRatio,
        fp.CommentPerViewRatio,
        fp.AdjustedScore,
        fp.TotalPosts,
        fp.AvgScore,
        fp.UserLevel,
        fp.VoteCount,
        fp.LastMajorEventDate,
        fp.PostStatus,
        fp.DuplicateCount,
        CASE 
            WHEN fp.DuplicateCount > 0 THEN 
                'High Risk Duplicate' 
            WHEN fp.CommentCount > 10 AND fp.ViewCount > 100 THEN 
                'High Engagement'
            WHEN fp.AnswerCount > 5 AND fp.ViewCount > 50 THEN 
                'Active Question'
            WHEN fp.Score < 0 THEN 
                'Low Rated'
            ELSE 'Normal'
        END AS PostClassification,
        RANK() OVER (
            PARTITION BY fp.UserLevel 
            ORDER BY fp.AdjustedScore DESC, fp.ViewCount DESC
        ) AS LevelRank,
        ROW_NUMBER() OVER (
            ORDER BY fp.Score DESC, fp.ViewCount DESC
        ) AS OverallRank,
        CASE 
            WHEN fp.Score = 0 AND fp.ViewCount = 0 THEN 'Inactive'
            WHEN fp.Score > 50 AND fp.Score < 100 THEN 'Noticeable'
            WHEN fp.Score >= 100 THEN 'Popular'
            ELSE 'Not Popular'
        END AS PopularityIndicator,
        DATEDIFF(DAY, fp.CreationDate, fp.LastActivityDate) AS ActivityAgeDays,
        (
            SELECT COUNT(DISTINCT t.TagName)
            FROM (
                SELECT TRIM(SUBSTRING(
                    SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2),
                    PATINDEX('%>%' + SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '>' + SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2)) + 1,
                    PATINDEX('%>%', SUBSTRING(p.Tags, PATINDEX('%>%' + SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '>' + SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2)) + 1, LEN(p.Tags))) - 1
                )) AS TagName
                FROM Posts p
                WHERE p.Id = fp.PostId
                AND p.Tags IS NOT NULL
                AND LEN(p.Tags) > 2
            ) t
        ) AS TagCount,
        (
            SELECT t1.Count
            FROM Tags t1
            WHERE t1.TagName LIKE '%sql%'
            AND t1.TagName IN (
                SELECT DISTINCT TRIM(SUBSTRING(
                    SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2),
                    PATINDEX('%>%' + SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '>' + SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2)) + 1,
                    PATINDEX('%>%', SUBSTRING(p.Tags, PATINDEX('%>%' + SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '>' + SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2)) + 1, LEN(p.Tags))) - 1
                ))
                FROM Posts p
                WHERE p.Id = fp.PostId
                AND p.Tags IS NOT NULL
                AND LEN(p.Tags) > 2
            )
        ) AS SqlTagCount,
        ROW_NUMBER() OVER (PARTITION BY fp.UserLevel, fp.ScoreCategory ORDER BY fp.AdjustedScore DESC) AS UserScoreRank,
        CASE 
            WHEN fp.ViewCount > 1000 THEN 'Viral'
            WHEN fp.ViewCount > 500 THEN 'Trending'
            WHEN fp.ViewCount > 100 THEN 'Notable'
            ELSE 'Obscure'
        END AS ViewRanking
    FROM FilteredPosts fp
),
FinalAnalysis AS (
    SELECT 
        cr.*,
        CASE 
            WHEN cr.TagCount > 2 THEN 'Multiple Tags'
            WHEN cr.TagCount = 1 THEN 'Single Tag'
            ELSE 'No Tags'
        END AS TagCategory,
        CASE 
            WHEN cr.SqlTagCount > 0 THEN 'SQL Related'
            WHEN cr.TagCount = 0 THEN 'No Tags'
            ELSE 'Other Tags'
        END AS TagRelevance,
        CASE 
            WHEN cr.ActivityAgeDays < 30 THEN 'Recently Active'
            WHEN cr.ActivityAgeDays BETWEEN 30 AND 180 THEN 'Moderately Active'
            WHEN cr.ActivityAgeDays > 180 THEN 'Inactive'
            ELSE 'Unknown'
        END AS ActivityStatus,
        CASE 
            WHEN cr.DuplicateCount > 0 THEN 
                CAST((cr.DuplicateCount * 100.0 / cr.AnswerCount) AS DECIMAL(5,2)) 
            ELSE 
                0 
        END AS DuplicatePercentage
    FROM CombinedResults cr
)
SELECT 
    *,
    ROW_NUMBER() OVER (ORDER BY FinalAnalysis.Score DESC, FinalAnalysis.ViewCount DESC) AS OverallPosition,
    RANK() OVER (ORDER BY FinalAnalysis.AdjustedScore DESC) AS AdjustedScoreRank,
    DENSE_RANK() OVER (ORDER BY FinalAnalysis.ViewCount DESC) AS ViewRank,
    PERCENT_RANK() OVER (ORDER BY FinalAnalysis.Score DESC) AS ScorePercentile,
    CUME_DIST() OVER (ORDER BY FinalAnalysis.ViewCount DESC) AS ViewPercentile,
    NTILE(10) OVER (ORDER BY FinalAnalysis.Score DESC) AS ScoreDecile,
    CASE 
        WHEN (FinalAnalysis.TagCount * FinalAnalysis.ViewCount) > 1000 THEN 'High Impact'
        WHEN (FinalAnalysis.TagCount * FinalAnalysis.ViewCount) > 500 THEN 'Medium Impact'
        WHEN (FinalAnalysis.TagCount * FinalAnalysis.ViewCount) > 100 THEN 'Low Impact'
        ELSE 'Minimal Impact'
    END AS ImpactCategory
FROM FinalAnalysis
HAVING FinalAnalysis.Score > 0
ORDER BY FinalAnalysis.Score DESC, FinalAnalysis.ViewCount DESC
LIMIT 1000 OFFSET 0;