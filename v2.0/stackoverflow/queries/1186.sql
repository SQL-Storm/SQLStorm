-- {"query": "1186.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3591}
WITH UserEngagementMetrics AS (
    SELECT
        U.Id AS UserId,
        U.CreationDate AS UserCreationDate,
        U.Reputation,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        U.LastAccessDate,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(P.ViewCount), 0) AS TotalViewsOnPosts,
        COALESCE(MAX(P.LastActivityDate), U.LastAccessDate) AS LastContentActivity,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.AnswerCount ELSE 0 END), 0) AS TotalAnswersToQuestionsReceived,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 AND P.AcceptedAnswerId IS NOT NULL AND P.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END), 0) AS AcceptedAnswersCount,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END), 0.0) AS AvgQuestionScore,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS CommentsMade
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.CreationDate, U.Reputation, U.UpVotes, U.DownVotes, U.LastAccessDate
),
PostEditAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS FirstEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 'True' ELSE 'False' END) AS WasClosedEver,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN crt.Name ELSE NULL END) AS LatestCloseReasonName,
        AVG(time_diff_seconds) AS AvgTimeBetweenEditsSeconds
    FROM (
        SELECT
            ph_inner.*,
            EXTRACT(EPOCH FROM (ph_inner.CreationDate - ph_prev.CreationDate)) AS time_diff_seconds,
            ph_prev.PostHistoryTypeId AS prev_type
        FROM PostHistory ph_inner
        LEFT JOIN LATERAL (
            SELECT ph2.PostId, ph2.CreationDate, ph2.PostHistoryTypeId
            FROM PostHistory ph2
            WHERE ph2.PostId = ph_inner.PostId
              AND ph2.CreationDate < ph_inner.CreationDate
            ORDER BY ph2.CreationDate DESC
            LIMIT 1
        ) ph_prev ON TRUE
    ) ph
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND CAST(ph.Comment AS SMALLINT) = crt.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6)
      AND ph.prev_type IN (4,5,6)
    GROUP BY ph.PostId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(CASE WHEN B.TagBased = TRUE THEN 'True' ELSE 'False' END) AS HasTagBasedBadge
    FROM Badges B
    GROUP BY B.UserId
),
TopTagPerUser AS (
    SELECT
        UserId,
        TagName,
        TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagPostCount DESC, TagName ASC) AS rn
    FROM (
        SELECT
            P.OwnerUserId AS UserId,
            TRIM(x.tag) AS TagName,
            COUNT(P.Id) AS TagPostCount
        FROM Posts P,
        LATERAL (
            SELECT UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS tag
        ) x
        WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
        GROUP BY P.OwnerUserId, TRIM(x.tag)
    ) AS UserTagCounts
),
PostLinkStats AS (
    SELECT
        P.Id AS PostId,
        COUNT(PL.RelatedPostId) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksCount,
        MAX(CASE WHEN EXISTS (SELECT 1 FROM PostLinks pl2 WHERE pl2.RelatedPostId = P.Id AND pl2.LinkTypeId = 3) THEN 'True' ELSE 'False' END) AS IsDuplicateTarget
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    GROUP BY P.Id
),
PostCommentRank AS (
    SELECT
        C.PostId,
        C.CreationDate AS CommentCreationDate,
        C.Score AS CommentScore,
        C.UserId AS CommenterId,
        ROW_NUMBER() OVER (PARTITION BY C.PostId ORDER BY C.CreationDate DESC) AS rn
    FROM Comments C
)
SELECT
    'HighTier_Engaged' AS UserGroupSegment,
    UEM.UserId,
    U.DisplayName,
    U.Reputation,
    UEM.UserCreationDate,
    AGE(TIMESTAMP '2024-10-01 12:34:56', UEM.LastContentActivity) AS TimeSinceLastActivity,
    UEM.QuestionsPosted,
    UEM.AnswersPosted,
    UEM.TotalPostScoreReceived,
    UEM.TotalViewsOnPosts,
    UEM.CommentsMade,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadgesCount,
    COALESCE(UBS.HasTagBasedBadge, 'False') AS HasTagBasedBadge,
    TTPU.TagName AS TopActiveTag,
    TTPU.TagPostCount AS TopTagPosts,
    COALESCE(UPPER(SUBSTRING(U.Location FROM 1 FOR 5)), 'UNKNOWN') AS LocationPrefix,
    LENGTH(COALESCE(U.AboutMe, '')) AS AboutMeLength,
    (U.WebsiteUrl IS NOT NULL) AS HasWebsite,
    CAST(UEM.AcceptedAnswersCount AS NUMERIC) / NULLIF(UEM.AnswersPosted, 0) AS AcceptedAnswerRate,
    (U.Reputation * 0.15 + UEM.TotalPostScoreReceived * 0.4 + UEM.QuestionsPosted * 0.2 + UEM.AnswersPosted * 0.15 + COALESCE(UBS.GoldBadges, 0) * 10 + COALESCE(UBS.SilverBadges, 0) * 5) AS UserActivityRankScore,
    (
        SELECT AVG(InnerU.Reputation)
        FROM Users InnerU
        JOIN Posts InnerP ON InnerU.Id = InnerP.OwnerUserId
        WHERE InnerP.PostTypeId = 1
          AND InnerP.Tags IS NOT NULL AND InnerP.Tags LIKE '%' || TTPU.TagName || '%'
          AND InnerU.Reputation > U.Reputation
          AND InnerU.LastAccessDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    ) AS AvgReputationOfHigherReputationTagMates,
    DENSE_RANK() OVER (ORDER BY (U.Reputation * 0.15 + UEM.TotalPostScoreReceived * 0.4 + UEM.QuestionsPosted * 0.2 + UEM.AnswersPosted * 0.15 + COALESCE(UBS.GoldBadges, 0) * 10 + COALESCE(UBS.SilverBadges, 0) * 5) DESC, U.Id ASC) AS OverallUserRank,
    (
        SELECT PEA.EditCount
        FROM Posts P_latest
        LEFT JOIN PostEditAnalysis PEA ON P_latest.Id = PEA.PostId
        WHERE P_latest.OwnerUserId = UEM.UserId AND P_latest.PostTypeId = 1
        ORDER BY P_latest.CreationDate DESC
        LIMIT 1
    ) AS LatestQuestionEditCount,
    (
        SELECT PLS.LinkedPostsCount
        FROM Posts P_latest
        LEFT JOIN PostLinkStats PLS ON P_latest.Id = PLS.PostId
        WHERE P_latest.OwnerUserId = UEM.UserId AND P_latest.PostTypeId = 1
        ORDER BY P_latest.CreationDate DESC
        LIMIT 1
    ) AS LatestQuestionLinkedPosts,
    (
        SELECT PCR.CommentScore
        FROM Posts P_latest
        LEFT JOIN PostCommentRank PCR ON P_latest.Id = PCR.PostId
        WHERE P_latest.OwnerUserId = UEM.UserId AND P_latest.PostTypeId = 1 AND PCR.rn = 1
        ORDER BY P_latest.CreationDate DESC
        LIMIT 1
    ) AS LatestQuestionLastCommentScore
FROM Users U
LEFT JOIN UserEngagementMetrics UEM ON U.Id = UEM.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN TopTagPerUser TTPU ON U.Id = TTPU.UserId AND TTPU.rn = 1
WHERE
    U.Reputation > 20000
    AND UEM.QuestionsPosted >= 10
    AND UEM.AnswersPosted >= 20
    AND UEM.LastContentActivity > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    AND U.DisplayName IS NOT NULL AND U.DisplayName <> ''
    AND (COALESCE(UBS.GoldBadges,0) >= 1 OR COALESCE(UBS.SilverBadges,0) >= 5 OR (U.Location IS NOT NULL AND U.Location ILIKE '%london%') OR (U.Location IS NOT NULL AND U.Location ILIKE '%new york%'))
UNION ALL
SELECT
    'MidTier_Active' AS UserGroupSegment,
    UEM.UserId,
    U.DisplayName,
    U.Reputation,
    UEM.UserCreationDate,
    AGE(TIMESTAMP '2024-10-01 12:34:56', UEM.LastContentActivity) AS TimeSinceLastActivity,
    UEM.QuestionsPosted,
    UEM.AnswersPosted,
    UEM.TotalPostScoreReceived,
    UEM.TotalViewsOnPosts,
    UEM.CommentsMade,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadgesCount,
    COALESCE(UBS.HasTagBasedBadge, 'False') AS HasTagBasedBadge,
    TTPU.TagName AS TopActiveTag,
    TTPU.TagPostCount AS TopTagPosts,
    COALESCE(UPPER(SUBSTRING(U.Location FROM 1 FOR 5)), 'UNKNOWN') AS LocationPrefix,
    LENGTH(COALESCE(U.AboutMe, '')) AS AboutMeLength,
    (U.WebsiteUrl IS NOT NULL) AS HasWebsite,
    CAST(UEM.AcceptedAnswersCount AS NUMERIC) / NULLIF(UEM.AnswersPosted, 0) AS AcceptedAnswerRate,
    (U.Reputation * 0.15 + UEM.TotalPostScoreReceived * 0.4 + UEM.QuestionsPosted * 0.2 + UEM.AnswersPosted * 0.15 + COALESCE(UBS.GoldBadges, 0) * 10 + COALESCE(UBS.SilverBadges, 0) * 5) AS UserActivityRankScore,
    (
        SELECT AVG(InnerU.Reputation)
        FROM Users InnerU
        JOIN Posts InnerP ON InnerU.Id = InnerP.OwnerUserId
        WHERE InnerP.PostTypeId = 1
          AND InnerP.Tags IS NOT NULL AND InnerP.Tags LIKE '%' || TTPU.TagName || '%'
          AND InnerU.Reputation > U.Reputation
          AND InnerU.LastAccessDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    ) AS AvgReputationOfHigherReputationTagMates,
    DENSE_RANK() OVER (ORDER BY (U.Reputation * 0.15 + UEM.TotalPostScoreReceived * 0.4 + UEM.QuestionsPosted * 0.2 + UEM.AnswersPosted * 0.15 + COALESCE(UBS.GoldBadges, 0) * 10 + COALESCE(UBS.SilverBadges, 0) * 5) DESC, U.Id ASC) AS OverallUserRank,
    (
        SELECT PEA.EditCount
        FROM Posts P_latest
        LEFT JOIN PostEditAnalysis PEA ON P_latest.Id = PEA.PostId
        WHERE P_latest.OwnerUserId = UEM.UserId AND P_latest.PostTypeId = 1
        ORDER BY P_latest.CreationDate DESC
        LIMIT 1
    ) AS LatestQuestionEditCount,
    (
        SELECT PLS.LinkedPostsCount
        FROM Posts P_latest
        LEFT JOIN PostLinkStats PLS ON P_latest.Id = PLS.PostId
        WHERE P_latest.OwnerUserId = UEM.UserId AND P_latest.PostTypeId = 1
        ORDER BY P_latest.CreationDate DESC
        LIMIT 1
    ) AS LatestQuestionLinkedPosts,
    (
        SELECT PCR.CommentScore
        FROM Posts P_latest
        LEFT JOIN PostCommentRank PCR ON P_latest.Id = PCR.PostId
        WHERE P_latest.OwnerUserId = UEM.UserId AND P_latest.PostTypeId = 1 AND PCR.rn = 1
        ORDER BY P_latest.CreationDate DESC
        LIMIT 1
    ) AS LatestQuestionLastCommentScore
FROM Users U
LEFT JOIN UserEngagementMetrics UEM ON U.Id = UEM.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN TopTagPerUser TTPU ON U.Id = TTPU.UserId AND TTPU.rn = 1
WHERE
    U.Reputation <= 20000 AND U.Reputation > 500
    AND UEM.QuestionsPosted BETWEEN 1 AND 9
    AND UEM.AnswersPosted BETWEEN 1 AND 19
    AND UEM.LastContentActivity > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months'
    AND U.DisplayName IS NOT NULL AND U.DisplayName <> ''
    AND (U.Location IS NOT NULL AND U.Location <> '')
    AND NOT (U.Reputation > 20000 AND UEM.QuestionsPosted >= 10 AND UEM.AnswersPosted >= 20 AND UEM.LastContentActivity > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year' AND U.DisplayName IS NOT NULL AND U.DisplayName <> '' AND (COALESCE(UBS.GoldBadges,0) >= 1 OR COALESCE(UBS.SilverBadges,0) >= 5 OR (U.Location IS NOT NULL AND U.Location ILIKE '%london%') OR (U.Location IS NOT NULL AND U.Location ILIKE '%new york%')))
ORDER BY OverallUserRank ASC, UserGroupSegment DESC, UserId ASC
LIMIT 2000;