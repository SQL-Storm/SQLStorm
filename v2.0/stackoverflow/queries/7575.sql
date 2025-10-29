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
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        DATE_PART('day', CAST(p.LastActivityDate AS timestamp) - CAST(p.CreationDate AS timestamp)) as DaysSinceCreation,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END as VoteCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as GlobalViewRank,
        NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreDecile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT ps.PostId) as TotalPosts,
        SUM(ps.Score) as TotalScore,
        AVG(ps.Score) as AvgScore,
        MAX(ps.CreationDate) as LastPostDate,
        DATE_PART('day', CAST(TIMESTAMP '2024-10-01 12:34:56' AS timestamp) - CAST(u.CreationDate AS timestamp)) as AccountAgeDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 5000 THEN 'Advanced'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        STRING_AGG(CAST(ps.PostId AS VARCHAR), ',' ORDER BY ps.CreationDate) as PostIds
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PrevTagCount,
        (t.Count - LAG(t.Count, 1) OVER (ORDER BY t.Count DESC)) as CountDiff
    FROM Tags t
    WHERE t.Count > 0
),
ComplexVotes AS (
    SELECT 
        v.Id as VoteId,
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        CASE 
            WHEN v.VoteTypeId = 2 THEN 'UpVote'
            WHEN v.VoteTypeId = 3 THEN 'DownVote'
            WHEN v.VoteTypeId = 8 THEN 'BountyStart'
            WHEN v.VoteTypeId = 9 THEN 'BountyClose'
            ELSE 'Other'
        END as VoteTypeDesc,
        CASE 
            WHEN v.UserId IS NULL THEN 'System'
            ELSE 'User'
        END as VoteSource,
        CASE 
            WHEN v.BountyAmount > 0 THEN CAST(v.BountyAmount AS VARCHAR) || ' points'
            ELSE 'No bounty'
        END as BountyInfo
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 8, 9)
),
QuestionTags AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Tags,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags <> '' THEN 
                TRIM(BOTH '<>' FROM ps.Tags)
            ELSE ''
        END as RawTagString
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
),
TagUsage AS (
    SELECT 
        tag AS TagName,
        COUNT(*) as UsageCount,
        AVG(CASE WHEN score_val > 0 THEN score_val ELSE 0 END) as AvgScoreForTag,
        COUNT(DISTINCT owneruid) as UniqueAuthors
    FROM (
        SELECT
            qt.PostId,
            ps2.Score as score_val,
            ps2.OwnerUserId as owneruid,
            TRIM(BOTH '<>' FROM UNNEST(string_to_array(qt.RawTagString, '><'))) as tag
        FROM QuestionTags qt
        JOIN PostStats ps2 ON qt.PostId = ps2.PostId
    ) sub
    WHERE tag IS NOT NULL AND tag <> ''
    GROUP BY tag
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalScore,
    ua.AvgScore,
    ua.LastPostDate,
    ua.AccountAgeDays,
    ua.ReputationLevel,
    ps.PostId,
    ps.PostTypeDesc,
    ps.Title,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.DaysSinceCreation,
    ps.VoteCategory,
    ps.UserPostRank,
    ps.TotalUserPosts,
    ps.AvgUserScore,
    ps.GlobalScoreRank,
    ps.GlobalViewRank,
    ps.ScoreDecile,
    ta.TagName,
    ta.TagCount,
    ta.PopularityLevel,
    ta.TagRank,
    ta.PrevTagCount,
    ta.CountDiff,
    cv.VoteId,
    cv.VoteTypeDesc,
    cv.VoteSource,
    cv.BountyInfo,
    tu.UsageCount,
    tu.AvgScoreForTag,
    tu.UniqueAuthors,
    CASE 
        WHEN ua.Reputation > 10000 AND ps.Score > 50 THEN 'Elite Questioner'
        WHEN ua.Reputation > 5000 AND ps.Score > 25 THEN 'Veteran Questioner'
        WHEN ua.Reputation > 1000 AND ps.Score > 10 THEN 'Active Questioner'
        ELSE 'Regular Questioner'
    END as QuestionerCategory,
    CASE 
        WHEN ps.Score > ps.AvgUserScore AND ps.ViewCount > ps.GlobalViewRank THEN 'AboveAverageEngagement'
        WHEN ps.Score < ps.AvgUserScore AND ps.ViewCount < ps.GlobalViewRank THEN 'BelowAverageEngagement'
        ELSE 'AverageEngagement'
    END as EngagementLevel,
    'User ' || ua.UserId || ' - Post ' || ps.PostId || ' - Tag ' || COALESCE(ta.TagName, '') as CompositeReference,
    COALESCE(ps.Title, ps.Body) as ContentDescription,
    CASE 
        WHEN ps.Tags IS NULL OR ps.Tags = '' THEN 'No Tags'
        WHEN ps.Tags LIKE '%<tag>%' THEN 'Has Tags'
        ELSE 'Formatted Tags'
    END as TagStatus,
    ps.CreationDate + (ps.DaysSinceCreation || ' days')::interval as CalculatedEnddate,
    COALESCE(ps.ViewCount, 0) + COALESCE(ps.AnswerCount, 0) as CombinedMetrics,
    CASE 
        WHEN ps.Tags IS NOT NULL AND ps.Tags <> '' THEN 
            CASE 
                WHEN TRIM(BOTH '<>' FROM ps.Tags) LIKE '%<%' THEN 'MultiTag'
                ELSE 'SingleTag'
            END
        ELSE 'NoTag'
    END as TagStructure,
    CASE 
        WHEN ua.Reputation >= 10000 THEN 'Gold'
        WHEN ua.Reputation >= 5000 THEN 'Silver'
        WHEN ua.Reputation >= 1000 THEN 'Bronze'
        ELSE 'Regular'
    END as ReputationTier
FROM UserActivity ua
INNER JOIN PostStats ps ON ua.UserId = ps.OwnerUserId
LEFT JOIN TagAnalysis ta ON ta.TagName IN (
    SELECT UNNEST(string_to_array(
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags <> '' THEN TRIM(BOTH '<>' FROM ps.Tags)
            ELSE ''
        END, '><'
    ))
)
LEFT JOIN ComplexVotes cv ON ps.PostId = cv.PostId
LEFT JOIN TagUsage tu ON ta.TagName = tu.TagName
WHERE ps.PostTypeId = 1 
    AND (ps.Score > 0 OR ps.ViewCount > 100)
    AND ua.TotalPosts > 1
    AND ua.Reputation >= 500
    AND ps.CreationDate >= (CAST(TIMESTAMP '2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalScore,
    ua.AvgScore,
    ua.LastPostDate,
    ua.AccountAgeDays,
    ua.ReputationLevel,
    ps.PostId,
    ps.PostTypeDesc,
    ps.Title,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.DaysSinceCreation,
    ps.VoteCategory,
    ps.UserPostRank,
    ps.TotalUserPosts,
    ps.AvgUserScore,
    ps.GlobalScoreRank,
    ps.GlobalViewRank,
    ps.ScoreDecile,
    ta.TagName,
    ta.TagCount,
    ta.PopularityLevel,
    ta.TagRank,
    ta.PrevTagCount,
    ta.CountDiff,
    cv.VoteId,
    cv.VoteTypeDesc,
    cv.VoteSource,
    cv.BountyInfo,
    tu.UsageCount,
    tu.AvgScoreForTag,
    tu.UniqueAuthors,
    ps.CreationDate,
    ps.Tags,
    ps.Body,
    ua.Reputation
HAVING 
    COUNT(cv.VoteId) > 0 
    OR COUNT(tu.UsageCount) > 0 
    OR MAX(ps.AnswerCount) > 0
ORDER BY 
    ps.GlobalScoreRank,
    ua.Reputation DESC,
    ps.Score DESC,
    ps.ViewCount DESC
OFFSET 100 ROWS
FETCH NEXT 100 ROWS ONLY;