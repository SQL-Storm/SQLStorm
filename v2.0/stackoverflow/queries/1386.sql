-- {"query": "1386.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3115} 
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 1), 0.0) AS AvgQuestionScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2), 0.0) AS AvgAnswerScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(AVG(c.Score), 0.0) AS AvgCommentScore,
        MAX(COALESCE(p.LastActivityDate, c.CreationDate, u.LastAccessDate)) AS LatestContributionDate
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserPostHistoryEngagement AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT phe.PostId) AS PostsWithHistory,
        SUM(phe.TotalHistoryEntries) AS TotalUserHistoryEntries,
        SUM(phe.EditCount) AS TotalUserEditCount,
        COALESCE(AVG(phe.AvgBodyEditLength), 0.0) AS AvgUserPostBodyEditLength
    FROM Posts AS p
    INNER JOIN (
        SELECT
            ph.PostId,
            COUNT(ph.Id) AS TotalHistoryEntries,
            COUNT(DISTINCT ph.UserId) AS DistinctEditors,
            SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS EditCount,
            COALESCE(AVG(LENGTH(ph.Text)) FILTER (WHERE ph.PostHistoryTypeId IN (5,8)), 0.0) AS AvgBodyEditLength
        FROM PostHistory AS ph
        WHERE ph.PostHistoryTypeId IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,19,20,35,36)
        GROUP BY ph.PostId
    ) AS phe ON p.Id = phe.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TagFrequencyAndInfluence AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS TaggedPostCount,
        COALESCE(SUM(p.ViewCount), 0) AS TotalTagViewCount,
        COALESCE(AVG(p.Score), 0.0) AS AvgTagPostScore,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, SUM(p.ViewCount) DESC) AS TagRank
    FROM Posts AS p
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS PostTag(tag_name)
    JOIN Tags AS t ON PostTag.tag_name = t.TagName
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 100
),
ControversialPostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesRec,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesRec,
        COUNT(c.Id) AS CommentCount,
        CASE
            WHEN SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 0
            THEN CAST(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NUMERIC) / SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
            ELSE 1000000 -- Effectively infinite downvote ratio for posts with no upvotes
        END AS DownvoteRatio,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS WasDeleted
    FROM Posts AS p
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 12)
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.OwnerUserId, p.Score
    HAVING SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) > 5
),
UserControversialSummary AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(DISTINCT PostId) AS ControversialPostsCount,
        COALESCE(AVG(Score), 0.0) AS AvgControversialPostScore,
        COALESCE(AVG(DownvoteRatio), 0.0) AS AvgControversialDownvoteRatio
    FROM ControversialPostMetrics
    WHERE DownvoteRatio > 0.5 OR WasClosed = 1 OR WasDeleted = 1
    GROUP BY OwnerUserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LatestContributionDate,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.AvgQuestionScore,
    uas.AvgAnswerScore,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    uphe.TotalUserHistoryEntries AS PostHistoryCount,
    uphe.TotalUserEditCount AS PostEditCount,
    ut.TopContributingTag,
    ut.TopTagPosts,
    ucs.ControversialPostsCount,
    ucs.AvgControversialPostScore,
    ucs.AvgControversialDownvoteRatio,
    (
        SELECT COALESCE(AVG(ans.Score), 0.0)
        FROM Posts AS q_ans
        JOIN Posts AS ans ON q_ans.Id = ans.ParentId
        WHERE q_ans.PostTypeId = 1
          AND ans.OwnerUserId = uas.UserId
          AND q_ans.ViewCount > 50000
          AND ans.CreationDate BETWEEN uas.UserCreationDate AND uas.LatestContributionDate
          AND q_ans.Score >= 5
    ) AS AvgAnswerScoreToHighViewQuestions,
    NTILE(5) OVER (ORDER BY uas.Reputation DESC, b.GoldBadges DESC, uas.TotalAnswers DESC) AS UserEngagementTier,
    SUBSTRING(u.AboutMe, 1, 50) AS AboutMeExcerpt,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    'HighEngagementImpact' AS UserCategory
FROM UserActivitySummary AS uas
INNER JOIN Users AS u ON uas.UserId = u.Id
LEFT JOIN (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
) AS b ON uas.UserId = b.UserId
LEFT JOIN UserPostHistoryEngagement AS uphe ON uas.UserId = uphe.UserId
LEFT JOIN UserControversialSummary AS ucs ON uas.UserId = ucs.UserId
LEFT JOIN (
    SELECT DISTINCT ON (p.OwnerUserId)
        p.OwnerUserId AS UserId,
        tfi.TagName AS TopContributingTag,
        tfi.TaggedPostCount AS TopTagPosts
    FROM Posts AS p
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS PostTag(tag_name)
    JOIN TagFrequencyAndInfluence AS tfi ON PostTag.tag_name = tfi.TagName
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    ORDER BY p.OwnerUserId, tfi.TagRank ASC, tfi.TaggedPostCount DESC
) AS ut ON uas.UserId = ut.UserId
WHERE uas.Reputation > 5000
  AND uas.TotalAnswers > 100
  AND uas.LatestContributionDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  AND (u.WebsiteUrl IS NOT NULL OR u.AboutMe IS NOT NULL)
  AND (b.GoldBadges >= 2 OR ucs.ControversialPostsCount >= 5)
  AND EXISTS (
      SELECT 1
      FROM Posts AS p_inner
      WHERE p_inner.OwnerUserId = uas.UserId
        AND p_inner.PostTypeId = 1
        AND p_inner.ViewCount > 1000
        AND p_inner.CreationDate < uas.LastAccessDate
        AND NOT EXISTS (
            SELECT 1
            FROM Comments AS c_inner
            WHERE c_inner.PostId = p_inner.Id
              AND c_inner.Score < 0
              AND c_inner.CreationDate > p_inner.LastActivityDate
        )
  )

UNION ALL

SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS LatestContributionDate,
    COALESCE(uas_union.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(uas_union.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(uas_union.AvgQuestionScore, 0.0) AS AvgQuestionScore,
    COALESCE(uas_union.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(b_union.GoldBadges, 0) AS GoldBadges,
    COALESCE(b_union.SilverBadges, 0) AS SilverBadges,
    COALESCE(b_union.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uphe_union.TotalUserHistoryEntries, 0) AS PostHistoryCount,
    COALESCE(uphe_union.TotalUserEditCount, 0) AS PostEditCount,
    NULL AS TopContributingTag,
    0 AS TopTagPosts,
    0 AS ControversialPostsCount,
    0.0 AS AvgControversialPostScore,
    0.0 AS AvgControversialDownvoteRatio,
    0.0 AS AvgAnswerScoreToHighViewQuestions,
    NTILE(5) OVER (ORDER BY u.Reputation DESC, COALESCE(b_union.GoldBadges, 0) DESC) AS UserEngagementTier,
    SUBSTRING(u.AboutMe, 1, 50) AS AboutMeExcerpt,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    'CommunityContributor' AS UserCategory
FROM Users AS u
LEFT JOIN UserActivitySummary AS uas_union ON u.Id = uas_union.UserId
LEFT JOIN (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
) AS b_union ON u.Id = b_union.UserId
LEFT JOIN UserPostHistoryEngagement AS uphe_union ON u.Id = uphe_union.UserId
WHERE u.Reputation > 1000
  AND u.LastAccessDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
  AND (
        EXISTS (SELECT 1 FROM Badges AS b_inner WHERE b_inner.UserId = u.Id AND b_inner.Class = 1 AND b_inner.TagBased = TRUE)
     OR EXISTS (SELECT 1 FROM PostHistory AS ph_inner WHERE ph_inner.UserId = u.Id AND ph_inner.PostHistoryTypeId IN (14, 15, 19, 20))
     OR EXISTS (SELECT 1 FROM Posts AS p_inner WHERE p_inner.OwnerUserId = u.Id AND p_inner.PostTypeId IN (3, 4, 5))
  )
ORDER BY
    UserCategory, UserEngagementTier, Reputation DESC
LIMIT 2000;