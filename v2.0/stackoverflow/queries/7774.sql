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
        COALESCE(p.Body, '') as Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
            WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
            WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
            ELSE 'Unknown'
        END as PostType,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Zero'
        END as ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) as TotalUserScore,
        p.Score - AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as ScoreVsUserAvg,
        CASE 
            WHEN p.AnswerCount IS NOT NULL AND p.AnswerCount > 0 THEN 
                CAST(p.Score AS DOUBLE PRECISION) / NULLIF(CAST(p.AnswerCount AS DOUBLE PRECISION), 0)
            ELSE NULL 
        END as ScorePerAnswer,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) as tag)
            ELSE 0
        END as TagCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= DATE '2020-01-01'
      AND (p.Score >= 0 OR p.Score IS NULL)
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
        u.LastAccessDate,
        COUNT(p.Id) as PostCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.Score) as MaxScore,
        MIN(p.CreationDate) as FirstPostDate,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)), ', ') as AllTags,
        CASE 
            WHEN COUNT(p.Id) > 0 THEN 
                CAST(EXTRACT(EPOCH FROM (MAX(p.CreationDate) - MIN(p.CreationDate))) / 86400 AS INTEGER)
            ELSE 0 
        END as ActiveDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100 
      AND u.CreationDate >= DATE '2018-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagFrequency,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(t.Count, 0) as TagCount,
        CASE 
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 50 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Low'
            ELSE 'Rare'
        END as Popularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByFrequency
    FROM Tags t
    WHERE t.Count IS NOT NULL AND t.Count > 0
),
PostsWithBadges AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        b.Id as BadgeId,
        b.Name as BadgeName,
        b.Date as BadgeDate,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            WHEN b.Class = 3 THEN 'Bronze'
            ELSE 'Unknown'
        END as BadgeClass,
        b.TagBased
    FROM Posts p
    LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE '2020-01-01'
      AND p.Score > 10
),
ComplexResults AS (
    SELECT 
        ps.PostId,
        ps.PostType,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.ScoreCategory,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.ScoreQuartile,
        ps.ScoreVsUserAvg,
        ps.ScorePerAnswer,
        ps.TagCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ua.UserId,
        ua.DisplayName as AuthorName,
        ua.Reputation,
        ua.PostCount,
        ua.TotalScore,
        ua.AvgScore,
        ua.ActiveDays,
        ta.TagName,
        ta.TagFrequency,
        ta.Popularity,
        pbb.BadgeName,
        pbb.BadgeClass,
        pbb.BadgeDate,
        CASE 
            WHEN ps.Score > 0 AND ps.Score < 10 THEN 'Low Engagement'
            WHEN ps.Score >= 10 AND ps.Score < 50 THEN 'Moderate Engagement' 
            WHEN ps.Score >= 50 THEN 'High Engagement'
            ELSE 'No Engagement'
        END as EngagementLevel,
        CASE 
            WHEN ps.AnswerCount IS NOT NULL AND ps.AnswerCount > 0 THEN 
                CAST(ps.AnswerCount AS DOUBLE PRECISION) / NULLIF(CAST(ps.ViewCount AS DOUBLE PRECISION), 0) 
            ELSE 0 
        END as AnswerToViewRatio,
        CASE 
            WHEN ps.TagCount > 0 THEN 
                CASE 
                    WHEN ps.Score >= 10 THEN 
                        ps.TagCount * ps.Score 
                    ELSE 
                        ps.TagCount 
                END
            ELSE 0 
        END as TagScoreComplex,
        COALESCE(ps.PrevScore, 0) as PriorScore,
        COALESCE(ps.NextScore, 0) as NextScore,
        NULLIF(ABS(ps.Score - ps.PrevScore), 0) as ScoreChange,
        CASE 
            WHEN ps.Score > 0 AND ps.ViewCount > 0 THEN 
                (ps.Score * 100.0) / ps.ViewCount
            ELSE 0
        END as ScoreToViewRatio,
        CASE 
            WHEN ps.ViewCount >= 1000 THEN 'High Traffic'
            WHEN ps.ViewCount >= 100 THEN 'Medium Traffic'
            ELSE 'Low Traffic'
        END as TrafficLevel,
        DENSE_RANK() OVER (ORDER BY ps.ViewCount DESC) as ViewRank,
        PERCENT_RANK() OVER (ORDER BY ps.Score) as ScorePercentile,
        RANK() OVER (PARTITION BY ps.PostTypeId ORDER BY ps.Score DESC) as TypeRank
    FROM PostStats ps
    INNER JOIN UserActivity ua ON ps.OwnerUserId = ua.UserId
    LEFT JOIN TagAnalysis ta ON ps.Tags LIKE '%' || ta.TagName || '%'
    LEFT JOIN PostsWithBadges pbb ON ps.PostId = pbb.PostId
    WHERE ua.PostCount >= 2
      AND ps.Score >= 0
)
SELECT 
    cr.PostId,
    cr.PostType,
    cr.Title,
    cr.Score,
    cr.ViewCount,
    cr.AnswerCount,
    cr.CommentCount,
    cr.ScoreCategory,
    cr.UserPostRank,
    cr.ScoreRank,
    cr.ScoreQuartile,
    cr.ScoreVsUserAvg,
    cr.ScorePerAnswer,
    cr.TagCount,
    cr.CreationDate,
    cr.LastActivityDate,
    cr.UserId,
    cr.AuthorName,
    cr.Reputation,
    cr.PostCount,
    cr.TotalScore,
    cr.AvgScore,
    cr.ActiveDays,
    cr.TagName,
    cr.TagFrequency,
    cr.Popularity,
    cr.BadgeName,
    cr.BadgeClass,
    cr.BadgeDate,
    cr.EngagementLevel,
    cr.AnswerToViewRatio,
    cr.TagScoreComplex,
    cr.PriorScore,
    cr.NextScore,
    cr.ScoreChange,
    cr.ScoreToViewRatio,
    cr.TrafficLevel,
    cr.ViewRank,
    cr.ScorePercentile,
    cr.TypeRank,
    CASE 
        WHEN cr.ScoreRank <= 10 THEN 'Top 10'
        WHEN cr.ScoreRank <= 50 THEN 'Top 50'
        WHEN cr.ScoreRank <= 100 THEN 'Top 100'
        ELSE 'Other'
    END as ScorePerformanceTier,
    CASE 
        WHEN cr.TagName IS NOT NULL AND cr.TagScoreComplex > 0 THEN 
            ('Tag: ' || cr.TagName || ' | Score Complex: ' || CAST(cr.TagScoreComplex AS VARCHAR))
        ELSE 'No Tag Analysis'
    END as TagAnalysisSummary
FROM ComplexResults cr
WHERE cr.ViewCount > 0
  AND (cr.Reputation IS NOT NULL AND cr.Reputation > 0)
  AND (cr.Score IS NOT NULL AND cr.Score >= 0)
  AND (cr.PostCount IS NOT NULL AND cr.PostCount > 0)
  AND cr.Title IS NOT NULL
  AND cr.Title != ''
ORDER BY cr.Score DESC, cr.ViewCount DESC
LIMIT 1000;