-- {"query": "7271.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1859} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                (COUNT(DISTINCT p.Id) * 100.0 / NULLIF((SELECT COUNT(*) FROM Posts), 0))
            ELSE 0 
        END as PostPercentage,
        CASE 
            WHEN COUNT(DISTINCT b.Id) > 0 THEN 
                AVG(CAST(b.Class AS FLOAT)) 
            ELSE NULL 
        END as AvgBadgeClass
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, Reputation DESC) as PostRank,
        DENSE_RANK() OVER (ORDER BY AvgBadgeClass ASC, TotalBadges DESC) as BadgeRank,
        NTILE(10) OVER (ORDER BY Reputation DESC) as ReputationDecile
    FROM UserActivityStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as HasAcceptedAnswer,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END as IsCommunityOwned,
        DATEDIFF(DAY, p.CreationDate, COALESCE(p.ClosedDate, p.LastActivityDate, p.CreationDate)) as PostDurationDays,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score >= 10 THEN 'HighValueQuestion'
            WHEN p.PostTypeId = 1 AND p.Score < 10 THEN 'LowValueQuestion'
            WHEN p.PostTypeId = 2 AND p.Score >= 5 THEN 'HighValueAnswer'
            WHEN p.PostTypeId = 2 AND p.Score < 5 THEN 'LowValueAnswer'
            ELSE 'Other'
        END as PostValueCategory,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountActual,
        ISNULL(p.Tags, '') as Tags,
        STRING_AGG(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), ',') WITHIN GROUP (ORDER BY p.Id) as AllTagList
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
             p.CreationDate, p.OwnerUserId, p.PostTypeId, p.AcceptedAnswerId, 
             p.ClosedDate, p.CommunityOwnedDate, p.Tags
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'LessPopular'
            ELSE 'Average'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) - t.Count as PopularityDifference,
        AVG(t.Count) OVER (ORDER BY t.Count ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as MovingAverageCount
    FROM Tags t
),
ComplexUserAnalysis AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.TotalPosts,
        ru.TotalComments,
        ru.TotalBadges,
        ru.PostPercentage,
        ru.AvgBadgeClass,
        ru.PostRank,
        ru.BadgeRank,
        ru.ReputationDecile,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ru.UserId AND p.PostTypeId = 1 AND p.Score >= 100) THEN 'TopQuestionCreator'
            WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ru.UserId AND p.PostTypeId = 2 AND p.Score >= 50) THEN 'TopAnswerer'
            WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ru.UserId AND b.Class = 1) THEN 'GoldBadgeHolder'
            ELSE 'RegularUser'
        END as UserCategory,
        CASE 
            WHEN (ru.TotalBadges > 50 AND ru.AvgBadgeClass < 2.0) THEN 'Achiever'
            WHEN (ru.TotalPosts > 1000 AND ru.Reputation > 100000) THEN 'Veteran'
            WHEN (ru.TotalComments > 100 AND ru.TotalPosts > 50) THEN 'Engaged'
            ELSE 'Standard'
        END as CommunityRole
    FROM RankedUsers ru
)
SELECT 
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT CASE WHEN ca.UserCategory = 'TopQuestionCreator' THEN ca.UserId END) as TopQuestionCreators,
    COUNT(DISTINCT CASE WHEN ca.UserCategory = 'TopAnswerer' THEN ca.UserId END) as TopAnswerers,
    COUNT(DISTINCT CASE WHEN ca.UserCategory = 'GoldBadgeHolder' THEN ca.UserId END) as GoldBadgeHolders,
    COUNT(DISTINCT CASE WHEN ca.CommunityRole = 'Veteran' THEN ca.UserId END) as VeteranUsers,
    ROUND(AVG(CAST(ca.Reputation AS FLOAT)), 2) as AvgReputation,
    SUM(CASE WHEN pa.IsClosed = 1 THEN 1 ELSE 0 END) as ClosedPosts,
    AVG(pa.Score) as AvgPostScore,
    SUM(pa.AnswerCount) as TotalAnswers,
    COUNT(*) as TotalPosts,
    ROUND(AVG(CAST(pa.ViewCount AS FLOAT)), 2) as AvgViewCount,
    COUNT(DISTINCT ta.TagName) as TotalTags,
    AVG(ta.TagCount) as AvgTagCount,
    STRING_AGG(DISTINCT CASE WHEN ta.TagPopularity = 'Popular' THEN ta.TagName END, ', ') as PopularTags,
    COUNT(DISTINCT CASE WHEN pa.PostValueCategory LIKE '%HighValue%' THEN pa.PostId END) as HighValuePosts,
    COUNT(DISTINCT CASE WHEN pa.PostValueCategory LIKE '%LowValue%' THEN pa.PostId END) as LowValuePosts,
    STRING_AGG(DISTINCT ca.DisplayName, ', ') as UserNames,
    STRING_AGG(DISTINCT pa.Title, ', ') as PostTitles,
    CASE 
        WHEN COUNT(*) > 0 THEN 
            (COUNT(DISTINCT CASE WHEN pa.IsClosed = 1 THEN pa.PostId END) * 100.0 / COUNT(*))
        ELSE 0 
    END as ClosedPercentage,
    MAX(pa.PostDurationDays) as MaxPostDuration,
    MIN(pa.PostDurationDays) as MinPostDuration,
    ROUND(AVG(CAST(pa.PostDurationDays AS FLOAT)), 2) as AvgPostDuration,
    STRING_AGG(DISTINCT SUBSTRING(pa.Tags, 2, LEN(pa.Tags)-2), ',') AS AllTagsList,
    COUNT(DISTINCT CASE WHEN ca.ReputationDecile = 1 THEN ca.UserId END) as TopDecileUsers,
    COUNT(DISTINCT CASE WHEN ca.ReputationDecile = 10 THEN ca.UserId END) as BottomDecileUsers,
    (SELECT COUNT(*) FROM Posts WHERE LastActivityDate >= DATEADD(DAY, -30, GETDATE())) as RecentActivityCount,
    (SELECT AVG(CAST(Count AS FLOAT)) FROM Tags WHERE Count > 0) as OverallTagAverage
FROM ComplexUserAnalysis ca
FULL OUTER JOIN PostAnalysis pa ON ca.UserId = pa.OwnerUserId
FULL OUTER JOIN TagAnalysis ta ON pa.Tags LIKE '%' + ta.TagName + '%'
WHERE (ca.UserId IS NOT NULL OR pa.PostId IS NOT NULL OR ta.TagName IS NOT NULL)
HAVING COUNT(*) > 0
ORDER BY ca.Reputation DESC, pa.Score DESC;
```