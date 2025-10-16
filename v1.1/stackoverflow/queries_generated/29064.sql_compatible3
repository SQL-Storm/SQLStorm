WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN AVG(p.Score) 
            ELSE 0 
        END AS AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CAST('2010-01-01 00:00:00' AS TIMESTAMP)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        uas.*,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) AS RankByRep,
        RANK() OVER (ORDER BY AvgPostScore DESC) AS RankByAvgScore,
        DENSE_RANK() OVER (ORDER BY BadgeCount DESC) AS RankByBadges
    FROM UserActivityStats uas
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDesc,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Moderately Voted'
            WHEN p.Score > 0 THEN 'Low Voted'
            ELSE 'No Votes'
        END AS VoteCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) AS ViewDecile
    FROM Posts p
    WHERE p.CreationDate >= CAST('2015-01-01 00:00:00' AS TIMESTAMP)
),
QuestionAnalysis AS (
    SELECT 
        pa.Id,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.PostTypeDesc,
        pa.VoteCategory,
        pa.UserPostRank,
        pa.GlobalScoreRank,
        pa.ViewDecile,
        CASE 
            WHEN pa.AnswerCount > 0 THEN (pa.CommentCount * 1.0 / pa.AnswerCount)
            ELSE NULL 
        END AS CommentsPerAnswer,
        CASE 
            WHEN pa.ViewCount > 0 THEN (pa.Score * 1.0 / pa.ViewCount)
            ELSE NULL 
        END AS ScorePerView,
        CASE 
            WHEN pa.AnswerCount > 0 THEN (pa.Score * 1.0 / pa.AnswerCount)
            ELSE NULL 
        END AS ScorePerAnswer,
        CASE 
            WHEN (pa.AnswerCount * pa.CommentCount) > 0 THEN 
                (pa.AnswerCount * pa.CommentCount * 1.0 / (pa.AnswerCount + pa.CommentCount))
            ELSE NULL
        END AS EngagementMetric
    FROM PostAnalysis pa
    WHERE pa.PostTypeId = 1
),
AnswerAnalysis AS (
    SELECT 
        pa.Id,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.PostTypeDesc,
        pa.VoteCategory,
        pa.UserPostRank,
        pa.GlobalScoreRank,
        pa.ViewDecile,
        pa.CommentCount AS CommentsPerAnswer,
        pa.Score * 1.0 / NULLIF(pa.ViewCount, 0) AS ScorePerView,
        CASE WHEN pa.AnswerCount > 0 THEN pa.Score * 1.0 / pa.AnswerCount ELSE NULL END AS ScorePerAnswer,
        CASE 
            WHEN (pa.AnswerCount * pa.CommentCount) > 0 THEN 
                (pa.AnswerCount * pa.CommentCount * 1.0 / (pa.AnswerCount + pa.CommentCount))
            ELSE NULL
        END AS EngagementMetric,
        CASE 
            WHEN pa.ParentId IS NOT NULL THEN 
                (SELECT qa.Score FROM Posts qa WHERE qa.Id = pa.ParentId)
            ELSE NULL 
        END AS ParentQuestionScore,
        CASE 
            WHEN pa.ParentId IS NOT NULL THEN 
                (SELECT qt.Title FROM Posts qt WHERE qt.Id = pa.ParentId)
            ELSE NULL 
        END AS ParentQuestionTitle
    FROM PostAnalysis pa
    WHERE pa.PostTypeId = 2
),
TagAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderately Popular'
            WHEN t.Count > 100 THEN 'Less Common'
            ELSE 'Rare'
        END AS PopularityCategory,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS PopularityRank,
        AVG(t.Count) OVER () AS AvgTagCount,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) AS PrevCount
    FROM Tags t
),
CombinedAnalysis AS (
    SELECT 
        ra.UserId,
        ra.DisplayName,
        ra.Reputation,
        ra.PostCount,
        ra.CommentCount,
        ra.BadgeCount,
        ra.LastPostDate,
        ra.LastCommentDate,
        ra.AvgPostScore,
        ra.AllTags,
        ra.RankByRep,
        ra.RankByAvgScore,
        ra.RankByBadges,
        qa.Id AS QuestionId,
        qa.Title AS QuestionTitle,
        qa.Score AS QuestionScore,
        qa.ViewCount AS QuestionViewCount,
        qa.CreationDate AS QuestionCreationDate,
        qa.Tags AS QuestionTags,
        qa.AnswerCount AS QuestionAnswerCount,
        qa.CommentCount AS QuestionCommentCount,
        qa.FavoriteCount AS QuestionFavoriteCount,
        qa.VoteCategory AS QuestionVoteCategory,
        qa.UserPostRank AS QuestionUserRank,
        qa.GlobalScoreRank AS QuestionGlobalRank,
        qa.ViewDecile AS QuestionViewDecile,
        qa.CommentsPerAnswer AS QuestionCommentsPerAnswer,
        qa.ScorePerView AS QuestionScorePerView,
        qa.ScorePerAnswer AS QuestionScorePerAnswer,
        qa.EngagementMetric AS QuestionEngagementMetric,
        aa.Id AS AnswerId,
        aa.Title AS AnswerTitle,
        aa.Score AS AnswerScore,
        aa.ViewCount AS AnswerViewCount,
        aa.CreationDate AS AnswerCreationDate,
        aa.Tags AS AnswerTags,
        aa.AnswerCount AS AnswerAnswerCount,
        aa.CommentCount AS AnswerCommentCount,
        aa.FavoriteCount AS AnswerFavoriteCount,
        aa.VoteCategory AS AnswerVoteCategory,
        aa.UserPostRank AS AnswerUserRank,
        aa.GlobalScoreRank AS AnswerGlobalRank,
        aa.ViewDecile AS AnswerViewDecile,
        aa.CommentsPerAnswer AS AnswerCommentsPerAnswer,
        aa.ScorePerView AS AnswerScorePerView,
        aa.ScorePerAnswer AS AnswerScorePerAnswer,
        aa.EngagementMetric AS AnswerEngagementMetric,
        aa.ParentQuestionScore,
        aa.ParentQuestionTitle,
        ta.Id AS TagId,
        ta.TagName,
        ta.Count AS TagCount,
        ta.PopularityCategory,
        ta.PopularityRank
    FROM RankedUsers ra
    LEFT JOIN QuestionAnalysis qa ON ra.UserId = qa.OwnerUserId
    LEFT JOIN AnswerAnalysis aa ON ra.UserId = aa.OwnerUserId
    LEFT JOIN TagAnalysis ta ON EXISTS (
        SELECT 1
        FROM (
            SELECT TRIM(value) AS tag
            FROM UNNEST(string_to_array(COALESCE(qa.Tags, ''), '>')) AS t(value)
        ) tags_sub
        WHERE tags_sub.tag <> '' AND tags_sub.tag = ta.TagName
    )
    WHERE ra.Reputation >= 5000
)
SELECT 
    COUNT(DISTINCT UserId) AS DistinctUserCount,
    COUNT(DISTINCT QuestionId) AS DistinctQuestionCount,
    COUNT(DISTINCT AnswerId) AS DistinctAnswerCount,
    COUNT(DISTINCT TagId) AS DistinctTagCount,
    AVG(Reputation) AS AvgReputation,
    AVG(PostCount) AS AvgPostCount,
    AVG(CommentCount) AS AvgCommentCount,
    AVG(BadgeCount) AS AvgBadgeCount,
    AVG(QuestionScore) AS AvgQuestionScore,
    AVG(AnswerScore) AS AvgAnswerScore,
    AVG(QuestionViewCount) AS AvgQuestionViewCount,
    AVG(AnswerViewCount) AS AvgAnswerViewCount,
    NULLIF(SUM(CASE WHEN QuestionScore > 0 THEN 1 ELSE 0 END), 0) * 1.0 / NULLIF(COUNT(QuestionId), 0) AS QuestionSuccessRate,
    NULLIF(SUM(CASE WHEN AnswerScore > 0 THEN 1 ELSE 0 END), 0) * 1.0 / NULLIF(COUNT(AnswerId), 0) AS AnswerSuccessRate,
    STRING_AGG(DISTINCT DisplayName, ', ') AS UserNames,
    STRING_AGG(DISTINCT QuestionTitle, ', ') AS QuestionTitles,
    STRING_AGG(DISTINCT AnswerTitle, ', ') AS AnswerTitles,
    STRING_AGG(DISTINCT TagName, ', ') AS TagNames,
    STRING_AGG(DISTINCT PopularityCategory, ', ') AS PopularityLevels
FROM CombinedAnalysis
WHERE UserId IS NOT NULL
GROUP BY 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    CommentCount,
    BadgeCount,
    LastPostDate,
    LastCommentDate,
    AvgPostScore,
    AllTags,
    RankByRep,
    RankByAvgScore,
    RankByBadges
HAVING 
    COUNT(DISTINCT QuestionId) > 0 
    OR COUNT(DISTINCT AnswerId) > 0 
    OR COUNT(DISTINCT TagId) > 0
ORDER BY 
    AvgReputation DESC,
    AvgPostScore DESC
FETCH FIRST 1000 ROWS ONLY;