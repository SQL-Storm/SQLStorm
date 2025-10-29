-- {"query": "7640.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2844} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) FILTER (WHERE p.Tags IS NOT NULL), ', ') as AllTags,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes, u.CreationDate
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostTypeDescription,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, p.LastActivityDate, CURRENT_TIMESTAMP)) as AgeInDays,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Well Voted'
            WHEN p.Score > 0 THEN 'Positive'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'Neutral'
        END as ScoreCategory,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousPostScore,
        NTH_VALUE(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as OverallBestScore,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRankWithinUser
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
DetailedBadges AS (
    SELECT 
        b.UserId,
        b.Name as BadgeName,
        b.Date as BadgeDate,
        b.Class,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            WHEN b.Class = 3 THEN 'Bronze'
            ELSE 'Unknown'
        END as BadgeClass,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class) as ClassBadgesCount
    FROM Badges b
    WHERE b.TagBased = 0
),
ComplexUserAnalysis AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.AvgPostScore,
        us.LastPostDate,
        us.ReputationRank,
        us.PostActivityRank,
        COALESCE(ROUND(us.AvgPostScore, 2), 0) as RoundedAvgScore,
        CASE 
            WHEN us.PostCount > 100 THEN 'Veteran Poster'
            WHEN us.PostCount > 50 THEN 'Experienced Poster'
            WHEN us.PostCount > 10 THEN 'Regular Poster'
            ELSE 'Occasional Poster'
        END as PosterActivityLevel,
        COALESCE(ROUND((CAST(us.CommentCount AS FLOAT) / NULLIF(us.PostCount, 0)) * 100, 2), 0) as CommentToPostRatio,
        ARRAY_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) FILTER (WHERE p.Tags IS NOT NULL)) as TagArray,
        CASE 
            WHEN LENGTH(us.AllTags) > 300 THEN CONCAT(SUBSTRING(us.AllTags, 1, 300), '...')
            ELSE us.AllTags
        END as TrimmedTags
    FROM UserStats us
    LEFT JOIN Posts p ON us.UserId = p.OwnerUserId AND p.Tags IS NOT NULL
    GROUP BY 
        us.UserId, 
        us.DisplayName, 
        us.Reputation, 
        us.PostCount, 
        us.CommentCount, 
        us.BadgeCount, 
        us.AvgPostScore, 
        us.LastPostDate, 
        us.ReputationRank, 
        us.PostActivityRank,
        us.AllTags
),
TagUsageAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count >= 1000 THEN 'Very Popular'
            WHEN t.Count >= 100 THEN 'Popular'
            WHEN t.Count >= 10 THEN 'Moderately Popular'
            ELSE 'Less Popular'
        END as PopularityLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as PopularityRank,
        RANK() OVER (ORDER BY t.Count DESC) as CountRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PreviousTagCount,
        t.Count - LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as CountDifferenceFromPrevious
    FROM Tags t
    WHERE t.Count > 50
)
SELECT 
    cua.UserId,
    cua.DisplayName,
    cua.Reputation,
    cua.PostCount,
    cua.CommentCount,
    cua.BadgeCount,
    cua.AvgPostScore,
    cua.RoundedAvgScore,
    cua.PosterActivityLevel,
    cua.CommentToPostRatio,
    cua.TrimmedTags,
    COALESCE(SUM(pa.Score), 0) as TotalPostScore,
    COALESCE(MAX(pa.Score), 0) as HighestPostScore,
    COALESCE(MIN(pa.Score), 0) as LowestPostScore,
    COUNT(pa.PostId) as PostsWithScore,
    COALESCE(AVG(CAST(pa.AgeInDays AS FLOAT)), 0) as AvgPostAge,
    STRING_AGG(DISTINCT pa.PostTypeDescription, ', ') as PostTypesUsed,
    COUNT(DISTINCT CASE WHEN pa.PostTypeId = 1 THEN pa.PostId END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN pa.PostTypeId = 2 THEN pa.PostId END) as AnswerCount,
    STRING_AGG(DISTINCT CASE WHEN pa.Score > 0 THEN pa.Title END, ' | ') as PositiveScoreTitles,
    STRING_AGG(DISTINCT CASE WHEN pa.Score < 0 THEN pa.Title END, ' | ') as NegativeScoreTitles,
    STRING_AGG(DISTINCT db.BadgeName, ', ') as BadgeNames,
    COUNT(DISTINCT db.BadgeName) as DistinctBadgeCount,
    STRING_AGG(DISTINCT CASE 
        WHEN db.Class = 1 THEN CONCAT(db.BadgeName, ' (Gold)')
        WHEN db.Class = 2 THEN CONCAT(db.BadgeName, ' (Silver)')
        WHEN db.Class = 3 THEN CONCAT(db.BadgeName, ' (Bronze)')
    END, ', ') as ClassifiedBadges,
    STRING_AGG(DISTINCT tua.TagName, ', ') as PopularTags,
    COUNT(DISTINCT tua.Id) as TagCount,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN pa.Score > 0 THEN pa.PostId END) > 0 
        THEN 'Active Poster'
        WHEN COUNT(DISTINCT CASE WHEN pa.Score < 0 THEN pa.PostId END) > 0 
        THEN 'Questionable Poster'
        ELSE 'Passive Poster'
    END as PosterStatus,
    CASE 
        WHEN COALESCE(SUM(pa.Score), 0) > 1000 THEN 'Highly Engaged'
        WHEN COALESCE(SUM(pa.Score), 0) > 500 THEN 'Moderately Engaged'
        WHEN COALESCE(SUM(pa.Score), 0) > 0 THEN 'Slightly Engaged'
        ELSE 'Unengaged'
    END as EngagementLevel,
    STRING_AGG(
        CASE 
            WHEN pa.Score > 0 THEN CONCAT(pa.Title, ' (', pa.Score, ')')
            ELSE NULL 
        END, ' | ' 
        ORDER BY pa.Score DESC
    ) FILTER (WHERE pa.Score > 0) as HighScoringPosts,
    COALESCE(ROUND(COUNT(pa.PostId) * 100.0 / NULLIF(SUM(COUNT(pa.PostId)) OVER (), 0), 2), 0) as PostPercentageOfAllPosts,
    LAG(COALESCE(SUM(pa.Score), 0), 1) OVER (ORDER BY cua.Reputation DESC) as PreviousUserScoreTotal,
    COALESCE(SUM(pa.Score), 0) - LAG(COALESCE(SUM(pa.Score), 0), 1) OVER (ORDER BY cua.Reputation DESC) as ScoreChangeFromPrevious,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(pa.Score), 0) DESC) as ScoreRank,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = cua.UserId AND p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) 
        THEN 'Has Accepted Answers'
        ELSE 'No Accepted Answers'
    END as HasAcceptedAnswers,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Votes v INNER JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = cua.UserId AND v.VoteTypeId = 2) 
        THEN 'Has Upvotes'
        ELSE 'No Upvotes'
    END as HasUpvotes,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = cua.UserId AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 30) 
        THEN 'Has Long Tags'
        ELSE 'No Long Tags'
    END as HasLongTags,
    COUNT(DISTINCT CASE WHEN pa.Score > 100 THEN pa.PostId END) as SuperHighScorePosts,
    ROUND(COUNT(DISTINCT CASE WHEN pa.Score > 100 THEN pa.PostId END) * 100.0 / NULLIF(COUNT(pa.PostId), 0), 2) as HighScorePostPercentage,
    STRING_AGG(DISTINCT CASE 
        WHEN pa.Score >= 0 AND pa.Score < 5 THEN 'Low Scoring' 
        WHEN pa.Score >= 5 AND pa.Score < 20 THEN 'Medium Scoring'
        WHEN pa.Score >= 20 THEN 'High Scoring'
        ELSE 'Neutral Scoring'
    END, ', ') as ScoreLevelDistribution
FROM ComplexUserAnalysis cua
LEFT JOIN PostAnalysis pa ON cua.UserId = pa.OwnerUserId
LEFT JOIN DetailedBadges db ON cua.UserId = db.UserId
LEFT JOIN TagUsageAnalysis tua ON EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = cua.UserId 
    AND p.Tags IS NOT NULL 
    AND (
        SELECT COUNT(*) 
        FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) as tag
        WHERE tag = tua.TagName
    ) > 0
)
WHERE cua.PostCount > 0
GROUP BY 
    cua.UserId, 
    cua.DisplayName, 
    cua.Reputation, 
    cua.PostCount, 
    cua.CommentCount, 
    cua.BadgeCount, 
    cua.AvgPostScore, 
    cua.RoundedAvgScore, 
    cua.PosterActivityLevel, 
    cua.CommentToPostRatio, 
    cua.TrimmedTags,
    cua.ReputationRank
HAVING 
    COUNT(pa.PostId) > 0
    AND (
        COUNT(pa.PostId) >= 5 
        OR EXISTS (SELECT 1 FROM DetailedBadges WHERE UserId = cua.UserId)
        OR EXISTS (SELECT 1 FROM TagUsageAnalysis WHERE TagName IN (SELECT UNNEST(STRING_TO_ARRAY(cua.TrimmedTags, ',')) WHERE LENGTH(UNNEST(STRING_TO_ARRAY(cua.TrimmedTags, ','))) > 3))
    )
ORDER BY COALESCE(SUM(pa.Score), 0) DESC, cua.Reputation DESC, cua.PostCount DESC
LIMIT 100;