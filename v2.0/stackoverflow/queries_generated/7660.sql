-- {"query": "7660.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3451} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Body,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) as RankByScore,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score >= 10 THEN 'Highly_Voted_Question'
            WHEN p.PostTypeId = 1 AND p.Score >= 5 THEN 'Moderate_Question'
            WHEN p.PostTypeId = 1 AND p.Score < 5 THEN 'Low_Question'
            WHEN p.PostTypeId = 2 AND p.Score >= 10 THEN 'Highly_Voted_Answer'
            WHEN p.PostTypeId = 2 AND p.Score >= 5 THEN 'Moderate_Answer'
            WHEN p.PostTypeId = 2 AND p.Score < 5 THEN 'Low_Answer'
            ELSE 'Other'
        END as PostCategory,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousPostDate,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                CASE WHEN ARRAY_LENGTH(string_to_array(trim(p.Tags, '<>'), '><'), 1) > 0 THEN 
                    ARRAY_LENGTH(string_to_array(trim(p.Tags, '<>'), '><'), 1)
                ELSE 0 END
            ELSE 0 
        END as TagCount,
        EXTRACT(YEAR FROM p.CreationDate) as PostYear,
        EXTRACT(MONTH FROM p.CreationDate) as PostMonth,
        CASE 
            WHEN p.LastActivityDate >= NOW() - INTERVAL '30 days' THEN 'Active'
            WHEN p.LastActivityDate >= NOW() - INTERVAL '90 days' THEN 'Inactive_30_90'
            ELSE 'Inactive_90+'
        END as ActivityStatus
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount as UserViews,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate as UserCreationDate,
        COUNT(DISTINCT ps.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) as AnswerCount,
        COUNT(DISTINCT ps.Id) FILTER (WHERE ps.Score > 0) as PositiveScorePosts,
        AVG(ps.Score) as AvgPostScore,
        MAX(ps.Score) as MaxPostScore,
        MAX(ps.ViewCount) as MaxViewCount,
        AVG(ps.AnswerCount) as AvgAnswerCount,
        AVG(ps.CommentCount) as AvgCommentCount,
        AVG(ps.FavoriteCount) as AvgFavoriteCount,
        MAX(ps.CreationDate) as LatestPostDate,
        MIN(ps.CreationDate) as EarliestPostDate,
        DATEDIFF('day', MIN(ps.CreationDate), MAX(ps.CreationDate)) as ActiveDays,
        (COUNT(DISTINCT ps.Id) * 1.0 / NULLIF(DATEDIFF('day', u.CreationDate, CURRENT_TIMESTAMP), 0)) as PostsPerDay,
        COALESCE(SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(DISTINCT ps.Id), 0), 0) as QuestionPercent,
        CASE WHEN COUNT(DISTINCT ps.Id) >= 10 THEN 'High_Engagement'
             WHEN COUNT(DISTINCT ps.Id) >= 5 THEN 'Medium_Engagement'
             ELSE 'Low_Engagement' END as EngagementLevel
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsRequired,
        t.IsModeratorOnly,
        CASE WHEN t.Count > 1000 THEN 'Popular_Tag'
             WHEN t.Count > 100 THEN 'Moderate_Tag'
             ELSE 'Niche_Tag' END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PrevTagCount,
        LAG(t.TagName, 1) OVER (ORDER BY t.Count DESC) as PrevTagName,
        FIRST_VALUE(t.TagName) OVER (ORDER BY t.Count DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as HighestCountTag,
        FIRST_VALUE(t.Count) OVER (ORDER BY t.Count DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as HighestTagCount
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
PostTagCorrelation AS (
    SELECT 
        ps.Id as PostId,
        ps.Title,
        ps.Tags,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.AnswerCount,
        ps.CommentCount,
        ps.ViewCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.PostCategory,
        CASE WHEN ps.Tags IS NOT NULL THEN 
            COALESCE(ARRAY_LENGTH(string_to_array(trim(ps.Tags, '<>'), '><'), 1), 0) 
        ELSE 0 END as NumTags,
        CASE WHEN ps.Tags IS NOT NULL THEN 
            CASE WHEN ps.Tags LIKE '%<%' THEN 'Has_Special_Tags' ELSE 'No_Special_Tags' END
        ELSE 'No_Tags' END as TagStatus,
        CASE 
            WHEN ps.PostTypeId = 1 AND ps.Tags IS NULL THEN 'Question_No_Tags'
            WHEN ps.PostTypeId = 1 AND ps.Tags IS NOT NULL THEN 'Question_With_Tags'
            WHEN ps.PostTypeId = 2 AND ps.Tags IS NULL THEN 'Answer_No_Tags'
            ELSE 'Answer_With_Tags'
        END as PostTagStatus,
        CASE WHEN ps.PostTypeId = 1 THEN 
            ps.AnswerCount * 1.0 / NULLIF(ps.ViewCount, 0) 
        ELSE NULL END as AvgAnswerPerView,
        CASE WHEN ps.Score > 0 THEN 
            ps.CommentCount * 1.0 / NULLIF(ps.Score, 0) 
        ELSE NULL END as CommentPerScore
    FROM PostStats ps
),
ComplexPostAnalysis AS (
    SELECT 
        pta.PostId,
        pta.Title,
        pta.Tags,
        pta.PostTypeId,
        pta.OwnerUserId,
        pta.Score,
        pta.AnswerCount,
        pta.CommentCount,
        pta.ViewCount,
        pta.FavoriteCount,
        pta.CreationDate,
        pta.PostCategory,
        pta.NumTags,
        pta.TagStatus,
        pta.PostTagStatus,
        pta.AvgAnswerPerView,
        pta.CommentPerScore,
        CASE 
            WHEN pta.AvgAnswerPerView >= 0.1 THEN 'High_Question_Activity' 
            WHEN pta.AvgAnswerPerView >= 0.05 THEN 'Medium_Question_Activity'
            ELSE 'Low_Question_Activity' 
        END as QuestionActivityLevel,
        CASE 
            WHEN pta.CommentPerScore >= 0.5 THEN 'High_Comment_Rate'
            WHEN pta.CommentPerScore >= 0.2 THEN 'Medium_Comment_Rate' 
            ELSE 'Low_Comment_Rate'
        END as CommentActivityLevel,
        CASE WHEN pta.NumTags > 0 THEN 
            CASE WHEN pta.NumTags > 5 THEN 'Many_Tags'
                 WHEN pta.NumTags > 2 THEN 'Some_Tags'
                 ELSE 'Few_Tags' END
        ELSE 'No_Tags' END as TagIntensity,
        CASE WHEN pta.Score >= 100 THEN 'Elite_Question'
             WHEN pta.Score >= 25 THEN 'Good_Question'
             WHEN pta.Score >= 0 THEN 'Average_Question'
             ELSE 'Low_Question' END as QuestionQuality,
        CASE WHEN pta.OwnerUserId IS NOT NULL THEN 
             COALESCE(ue.EngagementLevel, 'Unknown')
        ELSE 'No_Owner' END as UserEngagementLevel,
        CASE WHEN pta.Score > (SELECT AVG(Score) FROM PostStats ps2 WHERE ps2.PostTypeId = 1) THEN 'Above_Avg_Score'
             WHEN pta.Score > (SELECT AVG(Score) FROM PostStats ps3 WHERE ps3.PostTypeId = 2) THEN 'Above_Avg_Answer_Score'
             ELSE 'Below_Avg' END as ScorePerformance
    FROM PostTagCorrelation pta
    LEFT JOIN UserEngagement ue ON pta.OwnerUserId = ue.UserId
),
FinalPostAnalysis AS (
    SELECT 
        cpa.PostId,
        cpa.Title,
        cpa.Tags,
        cpa.PostTypeId,
        cpa.OwnerUserId,
        cpa.Score,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.ViewCount,
        cpa.FavoriteCount,
        cpa.CreationDate,
        cpa.PostCategory,
        cpa.NumTags,
        cpa.TagStatus,
        cpa.PostTagStatus,
        cpa.AvgAnswerPerView,
        cpa.CommentPerScore,
        cpa.QuestionActivityLevel,
        cpa.CommentActivityLevel,
        cpa.TagIntensity,
        cpa.QuestionQuality,
        cpa.UserEngagementLevel,
        cpa.ScorePerformance,
        CASE WHEN cpa.PostTypeId = 1 THEN 
            (cpa.AnswerCount * 100.0 / NULLIF(cpa.ViewCount, 0))
        ELSE NULL END as AnswerRate,
        CASE WHEN cpa.PostTypeId = 1 THEN 
            (cpa.CommentCount * 100.0 / NULLIF(cpa.ViewCount, 0))
        ELSE NULL END as CommentRate,
        CASE WHEN cpa.PostTypeId = 1 AND cpa.ViewCount > 0 THEN 
            (cpa.Score * 100.0 / cpa.ViewCount)
        ELSE NULL END as ScorePerView,
        DENSE_RANK() OVER (ORDER BY cpa.Score DESC) as RankByScore,
        PERCENT_RANK() OVER (ORDER BY cpa.Score) as PercentileRank,
        CASE 
            WHEN cpa.CommentCount >= 5 AND cpa.CommentCount <= 10 THEN 'Normal_Comment'
            WHEN cpa.CommentCount > 10 THEN 'High_Comment'
            ELSE 'Low_Comment' 
        END as CommentLevel,
        CASE 
            WHEN cpa.TagIntensity = 'Many_Tags' AND cpa.QuestionQuality = 'Elite_Question' THEN 'Elite_Tagged_Question'
            WHEN cpa.TagIntensity = 'Many_Tags' AND cpa.QuestionQuality = 'Good_Question' THEN 'Good_Tagged_Question'
            WHEN cpa.TagIntensity = 'Few_Tags' AND cpa.QuestionQuality = 'Elite_Question' THEN 'Elite_Sparse_Question'
            WHEN cpa.TagIntensity = 'No_Tags' AND cpa.QuestionQuality = 'Elite_Question' THEN 'Elite_Untagged_Question'
            ELSE 'Standard_Question' 
        END as QuestionComplexity,
        CASE 
            WHEN cpa.PostCategory LIKE '%Question%' THEN 
                COALESCE(ce.Name, 'No_Close_Reason')
            ELSE NULL 
        END as CloseReason,
        LAG(cpa.TagIntensity, 1) OVER (ORDER BY cpa.CreationDate) as PrevTagIntensity,
        LAG(cpa.Score, 1) OVER (ORDER BY cpa.CreationDate) as PrevScore
    FROM ComplexPostAnalysis cpa
    LEFT JOIN (
        SELECT DISTINCT p.Id, p.Title, p.OwnerUserId 
        FROM Posts p
        INNER JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    ) ce ON cpa.PostId = ce.Id
)
SELECT 
    fpa.PostId,
    fpa.Title,
    fpa.Tags,
    fpa.PostTypeId,
    fpa.OwnerUserId,
    fpa.Score,
    fpa.AnswerCount,
    fpa.CommentCount,
    fpa.ViewCount,
    fpa.FavoriteCount,
    fpa.CreationDate,
    fpa.PostCategory,
    fpa.NumTags,
    fpa.TagStatus,
    fpa.PostTagStatus,
    fpa.AvgAnswerPerView,
    fpa.CommentPerScore,
    fpa.QuestionActivityLevel,
    fpa.CommentActivityLevel,
    fpa.TagIntensity,
    fpa.QuestionQuality,
    fpa.UserEngagementLevel,
    fpa.ScorePerformance,
    fpa.AnswerRate,
    fpa.CommentRate,
    fpa.ScorePerView,
    fpa.RankByScore,
    fpa.PercentileRank,
    fpa.CommentLevel,
    fpa.QuestionComplexity,
    fpa.CloseReason,
    fpa.PrevTagIntensity,
    fpa.PrevScore,
    EXISTS (
        SELECT 1 
        FROM PostLinks pl 
        WHERE pl.PostId = fpa.PostId AND pl.LinkTypeId = 3
    ) as IsDuplicate,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = fpa.PostId AND v.VoteTypeId = 2), 
        0
    ) as UpVoteCount,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = fpa.PostId AND v.VoteTypeId = 3), 
        0
    ) as DownVoteCount,
    CASE 
        WHEN fpa.Score <= -10 THEN 'Critical'
        WHEN fpa.Score <= -5 THEN 'Low'
        WHEN fpa.Score < 0 THEN 'Negative'
        WHEN fpa.Score = 0 THEN 'Zero'
        WHEN fpa.Score <= 10 THEN 'Positive'
        WHEN fpa.Score <= 50 THEN 'High'
        ELSE 'Exceptional' 
    END as ScoreRating,
    LAG(fpa.Score, 1) OVER (ORDER BY fpa.CreationDate) as PreviousPostScore,
    ABS(fpa.Score - LAG(fpa.Score, 1) OVER (ORDER BY fpa.CreationDate)) as ScoreChange,
    CASE 
        WHEN fpa.QuestionActivityLevel = 'High_Question_Activity' AND fpa.QuestionQuality = 'Elite_Question' 
        THEN 'High_Efficiency_Question'
        WHEN fpa.QuestionActivityLevel = 'Low_Question_Activity' AND fpa.QuestionQuality = 'Low_Question' 
        THEN 'Low_Efficiency_Question'
        ELSE 'Normal_Question'
    END as EfficiencyRating
FROM FinalPostAnalysis fpa
WHERE 
    fpa.PostId IS NOT NULL 
    AND fpa.Score IS NOT NULL
    AND (fpa.PostTypeId = 1 OR fpa.PostTypeId = 2)
    AND fpa.CreationDate >= NOW() - INTERVAL '365 days'
ORDER BY 
    fpa.Score DESC,
    fpa.ViewCount DESC,
    fpa.CommentCount DESC
LIMIT 5000;