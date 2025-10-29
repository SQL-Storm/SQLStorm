-- {"query": "1116.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2857}
WITH UserActivityMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.UpVotes, 0) AS TotalUpVotes,
        COALESCE(u.DownVotes, 0) AS TotalDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score), 0.0) AS AvgPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COALESCE(AVG(c.Score), 0.0) AS AvgCommentScore,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (3600 * 24 * 365.25) AS AccountAgeYears,
        (
            (COALESCE(u.UpVotes, 0) * 0.5) +
            (COALESCE(SUM(p.Score), 0) * 1.0) +
            (COALESCE(SUM(c.Score), 0) * 0.2) -
            (COALESCE(u.DownVotes, 0) * 0.3) +
            (u.Reputation * 0.01)
        ) AS UserEngagementScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostContentMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        LENGTH(COALESCE(p.Body, '')) AS BodyLength,
        LENGTH(COALESCE(p.Title, '')) AS TitleLength,
        (
            SELECT COUNT(cm.Id)
            FROM Comments cm
            WHERE cm.PostId = p.Id
              AND cm.CreationDate BETWEEN p.CreationDate AND (p.CreationDate + INTERVAL '24 hours')
        ) AS InitialCommentCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 6, 8, 9) THEN 1 ELSE 0 END) AS SignificantEditCount,
        EXTRACT(EPOCH FROM (MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (5, 6))) - p.CreationDate) / 3600 AS TimeToFirstEditHours,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('1', '101') THEN 1 ELSE 0 END) AS WasClosedAsDuplicate,
        (
            SELECT COALESCE(MAX(ans.Score), 0)
            FROM Posts ans
            WHERE ans.Id = p.AcceptedAnswerId
              AND p.PostTypeId = 1
        ) AS AcceptedAnswerMaxScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastEditDate, p.LastActivityDate,
             p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.Tags, p.Body, p.Title, p.AcceptedAnswerId
),
TagPerformance AS (
    SELECT
        UPPER(TRIM(tag)) AS TagName,
        COUNT(p.Id) AS TaggedQuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalTagViews,
        MAX(p.CreationDate) AS LatestTagActivity
    FROM (
        SELECT p.*, UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2
    ) p
    GROUP BY UPPER(TRIM(tag))
    HAVING COUNT(p.Id) > 10
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    ua.UserId,
    ua.UserName,
    ua.Reputation,
    ua.AccountAgeYears,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgPostScore,
    ua.AvgCommentScore,
    ua.UserEngagementScore,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    RANK() OVER (ORDER BY ua.Reputation DESC, ua.UserEngagementScore DESC) AS ReputationRank,
    NTILE(10) OVER (ORDER BY ua.Reputation DESC) AS ReputationTier,
    COUNT(pcm.PostId) AS TotalPostsAnalyzed,
    AVG(pcm.Score) FILTER (WHERE pcm.PostTypeId = 1 AND pcm.AcceptedAnswerMaxScore > 0) AS AvgScoreOnQuestionsWithGoodAcceptedAnswer,
    AVG(pcm.ViewCount) FILTER (WHERE pcm.PostTypeId = 1 AND pcm.InitialCommentCount > 0) AS AvgViewsOnEngagingQuestions,
    SUM(pcm.SignificantEditCount) AS TotalSignificantEditsOnOwnedPosts,
    (
        SELECT tp.TagName
        FROM TagPerformance tp
        JOIN Posts p_inner ON p_inner.PostTypeId = 1
                           AND p_inner.OwnerUserId = ua.UserId
                           AND p_inner.Tags ILIKE ('%' || '<' || tp.TagName || '>' || '%')
        GROUP BY tp.TagName, tp.AvgQuestionScore, tp.TotalTagViews
        ORDER BY (tp.AvgQuestionScore * 0.7 + tp.TotalTagViews * 0.3) DESC
        LIMIT 1
    ) AS MostInfluentialTagForUser,
    AVG(
        CASE
            WHEN pcm.LastActivityDate IS NOT NULL AND pcm.PostCreationDate IS NOT NULL
            THEN 1.0 / (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - pcm.LastActivityDate)) / 86400.0 + 1)
            ELSE 0.0
        END
    ) AS AvgPostFreshnessScore,
    SUM(
        COALESCE(pcm.Score, 0) * (1.0 + COALESCE(pcm.InitialCommentCount, 0) / 10.0)
        * CASE
            WHEN pcm.Tags ILIKE '%<sql>%' OR pcm.Tags ILIKE '%<database>%' THEN 1.5
            WHEN pcm.Tags ILIKE '%<javascript>%' THEN 1.2
            WHEN pcm.Tags ILIKE '%<python>%' THEN 1.1
            ELSE 1.0
          END
        * COALESCE(NULLIF(SIGN(pcm.ViewCount - 100), -1), 0)
        * CASE WHEN pcm.WasClosedAsDuplicate = 1 THEN 0.5 ELSE 1.0 END
    ) AS WeightedOverallPostImpact
FROM UserActivityMetrics ua
LEFT JOIN PostContentMetrics pcm ON ua.UserId = pcm.OwnerUserId
LEFT JOIN UserBadgeSummary ubs ON ua.UserId = ubs.UserId
WHERE
    ua.Reputation >= 1000
    AND ua.TotalQuestions >= 1
    AND ua.TotalAnswers >= 1
    AND ua.AccountAgeYears >= 0.5
    AND ua.UserName IS NOT NULL
GROUP BY
    ua.UserId, ua.UserName, ua.Reputation, ua.AccountAgeYears, ua.TotalUpVotes, ua.TotalDownVotes,
    ua.TotalPosts, ua.TotalQuestions, ua.TotalAnswers, ua.AvgPostScore, ua.AvgCommentScore,
    ua.UserEngagementScore, ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges,
    ubs.TagBasedBadges
HAVING
    COUNT(pcm.PostId) > 5
    AND SUM(pcm.SignificantEditCount) > 0
    AND SUM(CASE WHEN pcm.PostTypeId = 1 AND pcm.AcceptedAnswerMaxScore > 0 THEN 1 ELSE 0 END) >= 1
ORDER BY
    ReputationRank ASC, WeightedOverallPostImpact DESC
LIMIT 100;