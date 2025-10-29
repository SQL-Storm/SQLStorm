-- {"query": "1837.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3511}
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, 'Anonymous User #' || CAST(u.Id AS TEXT)) AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate)) / (3600 * 24 * 365.25) AS AccountAgeYears,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        u.LastAccessDate AS LastUserActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostActivityAndHistory AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        AGE(CAST('2024-10-01 12:34:56' AS TIMESTAMP), p.CreationDate) AS PostAgeInterval,
        EXTRACT(EPOCH FROM AGE(CAST('2024-10-01 12:34:56' AS TIMESTAMP), p.CreationDate)) AS PostAgeInterval_seconds_approx,
        p.Score AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS ActualAnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount,
        (p.ClosedDate IS NOT NULL) AS IsClosed,
        (p.CommunityOwnedDate IS NOT NULL) AS IsCommunityOwned,
        (NULLIF(p.AcceptedAnswerId, -1) IS NOT NULL) AS HasAcceptedAnswer,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        TRIM(BOTH '>' FROM TRIM(BOTH '<' FROM p.Tags)) AS RawTagsString,
        (SELECT COUNT(DISTINCT ph_sub.Id)
         FROM PostHistory ph_sub
         WHERE ph_sub.PostId = p.Id
           AND ph_sub.PostHistoryTypeId IN (4, 5, 6)) AS TotalEditEvents,
        (SELECT MAX(ph_sub.CreationDate)
         FROM PostHistory ph_sub
         WHERE ph_sub.PostId = p.Id
           AND ph_sub.PostHistoryTypeId IN (4, 5, 6)) AS LastEditDateByHistory,
        COALESCE(MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 AND ph_close.Comment IS NOT NULL THEN ph_close.Comment ELSE NULL END), '-1') AS LatestCloseReasonIdString,
        COALESCE(MAX(crt.Name) FILTER (WHERE ph_close.PostHistoryTypeId = 10), 'N/A') AS LatestCloseReasonName,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT pl_linked.RelatedPostId) FILTER (WHERE pl_linked.LinkTypeId = 1) AS LinkedPostCount,
        COUNT(DISTINCT pl_duplicate.RelatedPostId) FILTER (WHERE pl_duplicate.LinkTypeId = 3) AS DuplicatePostCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON ph_close.Comment = CAST(crt.Id AS TEXT)
    LEFT JOIN PostLinks pl_linked ON p.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1
    LEFT JOIN PostLinks pl_duplicate ON p.Id = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score,
        p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate,
        p.CommunityOwnedDate, p.AcceptedAnswerId, p.Body, p.Title, p.Tags
),
TagAnalysis AS (
    SELECT
        pah.PostId,
        pah.OwnerUserId,
        pah.PostCreationDate,
        LOWER(TRIM(UNNEST(string_to_array(SUBSTRING(pah.RawTagsString FROM 2 FOR LENGTH(pah.RawTagsString) - 2), '><')))) AS TagName,
        pah.PostScore,
        pah.PostViewCount,
        pah.IsClosed
    FROM PostActivityAndHistory pah
    WHERE pah.RawTagsString IS NOT NULL AND pah.RawTagsString <> '' AND LENGTH(pah.RawTagsString) > 2
),
PrimaryPostTags AS (
    SELECT
        ta.PostId,
        ta.OwnerUserId,
        ta.PostCreationDate,
        ta.TagName AS PrimaryTagName,
        ta.PostScore,
        ta.PostViewCount,
        ta.IsClosed,
        ROW_NUMBER() OVER(PARTITION BY ta.PostId ORDER BY ta.TagName, ta.PostCreationDate) AS rn
    FROM TagAnalysis ta
),
TagPerformance AS (
    SELECT
        ppt.PrimaryTagName AS TagName,
        COUNT(DISTINCT ppt.PostId) AS QuestionsWithTag,
        SUM(ppt.PostScore) AS TotalTagScore,
        AVG(ppt.PostViewCount) AS AvgTagViewCount,
        SUM(CASE WHEN ppt.IsClosed THEN 1 ELSE 0 END) AS ClosedQuestionsWithTag,
        (SELECT COUNT(DISTINCT tp.Id) FROM Tags tp WHERE tp.TagName = ppt.PrimaryTagName) AS TagTableCount,
        COALESCE(MAX(CASE WHEN t.IsModeratorOnly THEN 1 ELSE 0 END), 0) AS IsModeratorOnlyTag,
        COALESCE(MAX(CASE WHEN t.IsRequired THEN 1 ELSE 0 END), 0) AS IsRequiredTag
    FROM PrimaryPostTags ppt
    LEFT JOIN Tags t ON ppt.PrimaryTagName = t.TagName
    WHERE ppt.rn = 1
    GROUP BY ppt.PrimaryTagName
),
TemporalPostRanking AS (
    SELECT
        pah.PostId,
        pah.OwnerUserId,
        ue.UserName,
        pah.PostCreationDate,
        DATE_TRUNC('month', pah.PostCreationDate) AS PostMonth,
        pah.PostScore,
        pah.PostViewCount,
        pah.ActualAnswerCount,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', pah.PostCreationDate) ORDER BY pah.PostScore DESC, pah.PostViewCount DESC) AS RankInMonthByScore,
        AVG(pah.PostScore) OVER (PARTITION BY pah.OwnerUserId ORDER BY pah.PostCreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS UserRollingAvgPostScore,
        SUM(pah.PostViewCount) OVER (PARTITION BY pah.OwnerUserId ORDER BY pah.PostCreationDate) AS UserCumulativeViewCount,
        NTILE(10) OVER (ORDER BY pah.PostScore DESC, pah.PostViewCount DESC) AS ScoreViewNtile
    FROM PostActivityAndHistory pah
    INNER JOIN UserEngagement ue ON pah.OwnerUserId = ue.UserId
    WHERE pah.PostTypeId = 1
),
HighlyEngagedUsers AS (
    SELECT
        ue.UserId, ue.UserName, ue.Reputation, ue.AccountAgeYears,
        ue.TotalQuestionsPosted, ue.TotalQuestionScore, ue.AvgQuestionViewCount,
        ue.GoldBadges, ue.SilverBadges, ue.BronzeBadges, ue.LastUserActivity
    FROM UserEngagement ue
    WHERE ue.Reputation > 5000 AND ue.TotalQuestionsPosted > 10 AND ue.GoldBadges >= 1
),
LongTermContributors AS (
    SELECT
        ue.UserId, ue.UserName, ue.Reputation, ue.AccountAgeYears,
        ue.TotalQuestionsPosted, ue.TotalQuestionScore, ue.AvgQuestionViewCount,
        ue.GoldBadges, ue.SilverBadges, ue.BronzeBadges, ue.LastUserActivity
    FROM UserEngagement ue
    WHERE ue.AccountAgeYears >= 5 AND ue.TotalQuestionsPosted > 20 AND ue.LastUserActivity > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
)
SELECT
    'HighlyEngaged' AS UserCategory,
    heu.UserId,
    heu.UserName,
    heu.Reputation,
    heu.TotalQuestionsPosted,
    heu.TotalQuestionScore,
    heu.AvgQuestionViewCount,
    heu.GoldBadges,
    heu.SilverBadges,
    heu.BronzeBadges,
    tpr.PostId,
    tpr.PostCreationDate,
    tpr.PostScore,
    tpr.PostViewCount,
    tpr.ActualAnswerCount,
    tpr.RankInMonthByScore,
    tpr.UserRollingAvgPostScore,
    tpr.UserCumulativeViewCount,
    tpr.ScoreViewNtile,
    pah.BodyLength,
    pah.TitleLength,
    pah.TotalEditEvents,
    pah.LastEditDateByHistory,
    pah.LatestCloseReasonName,
    pah.TotalComments,
    pah.LinkedPostCount,
    pah.DuplicatePostCount,
    tp.TagName AS PrimaryTag,
    tp.QuestionsWithTag AS PrimaryTagTotalQuestions,
    tp.TotalTagScore AS PrimaryTagScore,
    tp.AvgTagViewCount AS PrimaryTagAvgViews,
    (CASE WHEN pah.IsClosed THEN 'Closed' ELSE 'Open' END) AS PostStatus,
    (pah.BodyLength + COALESCE(pah.TitleLength, 0)) * COALESCE(pah.TotalEditEvents, 0) / GREATEST(1.0, pah.PostAgeInterval_seconds_approx) AS ContentUpdateEfficiencyScore,
    CASE
        WHEN tpr.ScoreViewNtile <= 2 THEN 'Top 20%'
        WHEN tpr.ScoreViewNtile <= 5 THEN 'Mid 20-50%'
        ELSE 'Bottom 50%'
    END AS PostPerformanceTier,
    COALESCE(LOWER(SUBSTRING(heu.UserName FROM 1 FOR 3)), 'zzz') || '_' || CAST(heu.UserId AS TEXT) AS UserShortIdString
FROM HighlyEngagedUsers heu
INNER JOIN TemporalPostRanking tpr ON heu.UserId = tpr.OwnerUserId
LEFT JOIN PostActivityAndHistory pah ON tpr.PostId = pah.PostId
LEFT JOIN PrimaryPostTags ppt ON tpr.PostId = ppt.PostId AND ppt.rn = 1
LEFT JOIN TagPerformance tp ON ppt.PrimaryTagName = tp.TagName
WHERE tpr.RankInMonthByScore <= 10
  AND tpr.ScoreViewNtile <= 5
  AND pah.PostAgeInterval_seconds_approx IS NOT NULL
  AND pah.PostCreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 years'
  AND (pah.LatestCloseReasonName IS NULL OR pah.LatestCloseReasonName NOT IN ('Duplicate', 'Off-topic'))
  AND pah.PostViewCount > 100
UNION ALL
SELECT
    'LongTermContributor' AS UserCategory,
    ltc.UserId,
    ltc.UserName,
    ltc.Reputation,
    ltc.TotalQuestionsPosted,
    ltc.TotalQuestionScore,
    ltc.AvgQuestionViewCount,
    ltc.GoldBadges,
    ltc.SilverBadges,
    ltc.BronzeBadges,
    tpr.PostId,
    tpr.PostCreationDate,
    tpr.PostScore,
    tpr.PostViewCount,
    tpr.ActualAnswerCount,
    tpr.RankInMonthByScore,
    tpr.UserRollingAvgPostScore,
    tpr.UserCumulativeViewCount,
    tpr.ScoreViewNtile,
    pah.BodyLength,
    pah.TitleLength,
    pah.TotalEditEvents,
    pah.LastEditDateByHistory,
    pah.LatestCloseReasonName,
    pah.TotalComments,
    pah.LinkedPostCount,
    pah.DuplicatePostCount,
    tp.TagName AS PrimaryTag,
    tp.QuestionsWithTag AS PrimaryTagTotalQuestions,
    tp.TotalTagScore AS PrimaryTagScore,
    tp.AvgTagViewCount AS PrimaryTagAvgViews,
    (CASE WHEN pah.IsClosed THEN 'Closed' ELSE 'Open' END) AS PostStatus,
    (pah.BodyLength + COALESCE(pah.TitleLength, 0)) * COALESCE(pah.TotalEditEvents, 0) / GREATEST(1.0, pah.PostAgeInterval_seconds_approx) AS ContentUpdateEfficiencyScore,
    CASE
        WHEN tpr.ScoreViewNtile <= 2 THEN 'Top 20%'
        WHEN tpr.ScoreViewNtile <= 5 THEN 'Mid 20-50%'
        ELSE 'Bottom 50%'
    END AS PostPerformanceTier,
    COALESCE(UPPER(SUBSTRING(ltc.UserName FROM 1 FOR 3)), 'ZZZ') || '_' || CAST(ltc.UserId AS TEXT) AS UserShortIdString
FROM LongTermContributors ltc
INNER JOIN TemporalPostRanking tpr ON ltc.UserId = tpr.OwnerUserId
LEFT JOIN PostActivityAndHistory pah ON tpr.PostId = pah.PostId
LEFT JOIN PrimaryPostTags ppt ON tpr.PostId = ppt.PostId AND ppt.rn = 1
LEFT JOIN TagPerformance tp ON ppt.PrimaryTagName = tp.TagName
WHERE tpr.PostScore > 50
  AND tpr.UserRollingAvgPostScore > 20
  AND pah.HasAcceptedAnswer IS TRUE
  AND pah.TotalComments > 5
  AND pah.PostCreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years'
ORDER BY UserCategory, Reputation DESC, PostCreationDate DESC
LIMIT 5000;